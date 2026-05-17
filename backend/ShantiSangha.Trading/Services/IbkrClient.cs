using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Amazon.Lambda;
using Amazon.Lambda.Model;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Trading.Services;

/// <summary>
/// Invokes the wisecat Python Lambda for IBKR actions. Auth = IAM (the
/// same task role used by `MarketDataClient`). The Lambda holds the
/// IBKR OAuth 1.0a access token + signing key in AWS Secrets Manager and
/// signs requests to api.ibkr.com on every call.
///
/// We keep IIbkrClient as a separate interface (not folded into
/// MarketDataClient) so the broker integration can later move to a
/// dedicated Lambda — only the function name binding changes.
/// </summary>
public class IbkrClient(
    IAmazonLambda lambda,
    WisecatLambdaConfig config,
    ILogger<IbkrClient> logger) : IIbkrClient
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public async Task<IbkrAuthStatus> GetAuthStatusAsync(CancellationToken ct = default)
    {
        var resp = await InvokeAsync<AuthStatusResponseDto>(new { action = "ibkrAuthStatus" }, ct);
        if (resp is null) return new IbkrAuthStatus(false, false, false);
        return new IbkrAuthStatus(resp.Authenticated, resp.Connected, resp.Competing);
    }

    public Task<IbkrAuthStatus> TickleAsync(CancellationToken ct = default) =>
        // OAuth tokens don't need a /tickle keepalive — they're long-lived.
        // We keep the interface symmetric so the sync service code is portable
        // back to gateway-mode if we ever need it.
        GetAuthStatusAsync(ct);

    public async Task<IReadOnlyList<IbkrAccountSummary>> GetAccountsAsync(CancellationToken ct = default)
    {
        var resp = await InvokeAsync<AccountsResponseDto>(new { action = "ibkrAccounts" }, ct);
        if (resp?.Accounts is null) return Array.Empty<IbkrAccountSummary>();
        return resp.Accounts
            .Where(a => !string.IsNullOrEmpty(a.AccountId))
            .Select(a => new IbkrAccountSummary(a.AccountId!, a.Currency))
            .ToList();
    }

    public async Task<IReadOnlyList<IbkrPosition>> GetPositionsAsync(string accountId, CancellationToken ct = default)
    {
        var resp = await InvokeAsync<PositionsResponseDto>(new
        {
            action = "ibkrPositions",
            accountId,
        }, ct);
        if (resp?.Positions is null) return Array.Empty<IbkrPosition>();
        return resp.Positions
            .Select(p => new IbkrPosition(
                Conid: p.Conid,
                Ticker: p.Ticker,
                ContractDesc: p.ContractDesc,
                Position: p.Position,
                AvgCost: p.AvgCost,
                Currency: p.Currency ?? "USD",
                AssetClass: p.AssetClass ?? "STK"))
            .ToList();
    }

    public async Task<IReadOnlyList<IbkrLedgerEntry>> GetLedgerAsync(string accountId, CancellationToken ct = default)
    {
        var resp = await InvokeAsync<LedgerResponseDto>(new
        {
            action = "ibkrLedger",
            accountId,
        }, ct);
        if (resp?.Entries is null) return Array.Empty<IbkrLedgerEntry>();
        return resp.Entries
            .Where(e => !string.IsNullOrEmpty(e.Currency))
            .Select(e => new IbkrLedgerEntry(e.Currency!, e.CashBalance))
            .ToList();
    }

    public async Task<IbkrContractInfo?> ResolveContractAsync(long conid, CancellationToken ct = default)
    {
        var resp = await InvokeAsync<ContractInfoResponseDto>(new
        {
            action = "ibkrContractInfo",
            conid,
        }, ct);
        if (resp is null) return null;
        return new IbkrContractInfo(conid, resp.Ticker ?? resp.Symbol, resp.CompanyName);
    }

    // ---------- Lambda plumbing (mirrors MarketDataClient.InvokeAsync) -----

    private async Task<T?> InvokeAsync<T>(object payload, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(payload, JsonOpts);
        var req = new InvokeRequest
        {
            FunctionName = config.FunctionName,
            InvocationType = InvocationType.RequestResponse,
            Payload = json,
        };

        InvokeResponse resp;
        try
        {
            resp = await lambda.InvokeAsync(req, ct);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "wisecat IBKR Lambda invoke failed");
            return default;
        }

        var body = ReadStream(resp.Payload);

        if (!string.IsNullOrEmpty(resp.FunctionError))
        {
            // Python raised. If the error is OAuth-rejected, surface it as
            // IbkrUnauthorizedException so the sync service flips status to
            // NeedsReauth. Anything else is a generic failure.
            logger.LogWarning("wisecat IBKR Lambda FunctionError={Error}: {Body}", resp.FunctionError, body);
            if (body.Contains("ibkr_unauthorized", StringComparison.OrdinalIgnoreCase))
            {
                throw new IbkrUnauthorizedException("IBKR rejected the OAuth-signed request — re-link required.");
            }
            return default;
        }

        if (string.IsNullOrEmpty(body)) return default;

        // The Python side returns {"error": "ibkr_unauthorized", ...} for
        // 401 responses from api.ibkr.com (vs. raising). Catch that shape
        // before deserializing into T.
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("error", out var err)
                && err.ValueKind == JsonValueKind.String
                && string.Equals(err.GetString(), "ibkr_unauthorized", StringComparison.OrdinalIgnoreCase))
            {
                throw new IbkrUnauthorizedException("IBKR rejected the OAuth-signed request — re-link required.");
            }
        }
        catch (JsonException)
        {
            // fall through — let typed deserialization log the right error
        }

        try
        {
            return JsonSerializer.Deserialize<T>(body, JsonOpts);
        }
        catch (JsonException e)
        {
            logger.LogWarning(e, "IBKR response deserialization failed: {Body}", body);
            return default;
        }
    }

    private static string ReadStream(Stream? stream)
    {
        if (stream is null) return string.Empty;
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    // ---------- DTOs (match the Python Lambda wire format) ----------------

    private record AuthStatusResponseDto(bool Authenticated, bool Connected, bool Competing);

    private record AccountsResponseDto(List<AccountDto>? Accounts);
    private record AccountDto(
        [property: JsonPropertyName("accountId")] string? AccountId,
        [property: JsonPropertyName("currency")] string? Currency);

    private record PositionsResponseDto(List<PositionDto>? Positions);
    private record PositionDto(
        [property: JsonPropertyName("conid")] long Conid,
        [property: JsonPropertyName("ticker")] string? Ticker,
        [property: JsonPropertyName("contractDesc")] string? ContractDesc,
        [property: JsonPropertyName("position")] decimal Position,
        [property: JsonPropertyName("avgCost")] decimal AvgCost,
        [property: JsonPropertyName("currency")] string? Currency,
        [property: JsonPropertyName("assetClass")] string? AssetClass);

    private record LedgerResponseDto(List<LedgerEntryDto>? Entries);
    private record LedgerEntryDto(
        [property: JsonPropertyName("currency")] string? Currency,
        [property: JsonPropertyName("cashBalance")] decimal CashBalance);

    private record ContractInfoResponseDto(
        [property: JsonPropertyName("ticker")] string? Ticker,
        [property: JsonPropertyName("symbol")] string? Symbol,
        [property: JsonPropertyName("companyName")] string? CompanyName);
}
