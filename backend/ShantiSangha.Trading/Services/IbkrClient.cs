using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Trading.Services;

/// <summary>
/// HTTP client for the IBKR Client Portal Gateway. The gateway is a Java
/// sidecar running in the same ECS task on localhost. IBKR requires the
/// gateway for Individual accounts — OAuth 2.0 / private_key_jwt is
/// reserved for Institutional/Advisor accounts.
///
/// Session lifecycle is session-cookie based, owned by the Gateway. The
/// user authenticates with IBKR + 2FA once per ~24h via a browser hitting
/// the YARP-proxied gateway URL. The cookie persists on EFS so container
/// restarts don't force a re-auth.
///
/// Base URL is injected via DI (typed HttpClient); the typical value is
/// `http://localhost:5000` (or `https://localhost:5000` with TLS
/// validation disabled at the HttpClientHandler level — handled in
/// DependencyInjection.cs).
/// </summary>
public class IbkrClient(HttpClient http, ILogger<IbkrClient> logger) : IIbkrClient
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    // All Client Portal endpoints live under /v1/api/.
    private const string ApiPrefix = "/v1/api";

    public async Task<IbkrAuthStatus> GetAuthStatusAsync(CancellationToken ct = default)
    {
        var dto = await GetJsonAsync<AuthStatusDto>($"{ApiPrefix}/iserver/auth/status", ct);
        return new IbkrAuthStatus(
            dto?.Authenticated ?? false,
            dto?.Connected ?? false,
            dto?.Competing ?? false);
    }

    public async Task<IbkrAuthStatus> TickleAsync(CancellationToken ct = default)
    {
        // /tickle returns a payload whose "iserver.authStatus" field mirrors
        // /iserver/auth/status. We don't care about the rest.
        var dto = await PostJsonAsync<TickleResponseDto>($"{ApiPrefix}/tickle", null, ct);
        var auth = dto?.IServer?.AuthStatus;
        return new IbkrAuthStatus(
            auth?.Authenticated ?? false,
            auth?.Connected ?? false,
            auth?.Competing ?? false);
    }

    public async Task<IReadOnlyList<IbkrAccountSummary>> GetAccountsAsync(CancellationToken ct = default)
    {
        var rows = await GetJsonAsync<List<AccountDto>>($"{ApiPrefix}/portfolio/accounts", ct);
        if (rows is null) return Array.Empty<IbkrAccountSummary>();
        return rows
            .Where(r => !string.IsNullOrEmpty(r.AccountId))
            .Select(r => new IbkrAccountSummary(r.AccountId!, r.Currency))
            .ToList();
    }

    public async Task<IReadOnlyList<IbkrPosition>> GetPositionsAsync(string accountId, CancellationToken ct = default)
    {
        // IBKR paginates positions in pages of 100; for v1 we assume < 100
        // holdings. Page numbering starts at 0.
        var rows = await GetJsonAsync<List<PositionDto>>(
            $"{ApiPrefix}/portfolio/{Uri.EscapeDataString(accountId)}/positions/0", ct);
        if (rows is null) return Array.Empty<IbkrPosition>();
        return rows
            .Select(r => new IbkrPosition(
                Conid: r.Conid,
                Ticker: r.Ticker,
                ContractDesc: r.ContractDesc,
                Position: r.Position,
                AvgCost: r.AvgCost,
                Currency: r.Currency ?? "USD",
                AssetClass: r.AssetClass ?? "STK"))
            .ToList();
    }

    public async Task<IReadOnlyList<IbkrLedgerEntry>> GetLedgerAsync(string accountId, CancellationToken ct = default)
    {
        // The ledger response is a dict keyed by currency code (or "BASE").
        // System.Text.Json maps it to a Dictionary cleanly.
        var dict = await GetJsonAsync<Dictionary<string, LedgerEntryDto>>(
            $"{ApiPrefix}/portfolio/{Uri.EscapeDataString(accountId)}/ledger", ct);
        if (dict is null) return Array.Empty<IbkrLedgerEntry>();
        return dict
            .Where(kv => !string.Equals(kv.Key, "BASE", StringComparison.OrdinalIgnoreCase))
            .Select(kv => new IbkrLedgerEntry(
                Currency: kv.Value.Currency ?? kv.Key,
                CashBalance: kv.Value.CashBalance))
            .ToList();
    }

    public async Task<IbkrContractInfo?> ResolveContractAsync(long conid, CancellationToken ct = default)
    {
        var dto = await GetJsonAsync<ContractInfoDto>($"{ApiPrefix}/iserver/contract/{conid}/info", ct);
        if (dto is null) return null;
        return new IbkrContractInfo(conid, dto.Ticker ?? dto.Symbol, dto.CompanyName);
    }

    // ---------- HTTP plumbing ----------------------------------------------

    private async Task<T?> GetJsonAsync<T>(string path, CancellationToken ct)
    {
        using var resp = await http.GetAsync(path, ct);
        return await HandleResponseAsync<T>(resp, "GET", path, ct);
    }

    private async Task<T?> PostJsonAsync<T>(string path, object? body, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, path);
        if (body is not null)
        {
            req.Content = new StringContent(JsonSerializer.Serialize(body, JsonOpts));
            req.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        }
        else
        {
            // IBKR's /tickle and /sso/validate accept zero-length bodies but
            // some intermediaries object to missing Content-Type. Send empty
            // JSON.
            req.Content = new StringContent("{}");
            req.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        }
        using var resp = await http.SendAsync(req, ct);
        return await HandleResponseAsync<T>(resp, "POST", path, ct);
    }

    private async Task<T?> HandleResponseAsync<T>(HttpResponseMessage resp, string verb, string path, CancellationToken ct)
    {
        // The gateway returns 401 when its own session has expired (rare —
        // requires the gateway to assert that itself) and 403 when there's
        // no IBKR session at all (the common pre-login state). Both should
        // surface as IbkrUnauthorizedException so the sync service flips
        // status to NeedsReauth and the controller returns a friendly 400
        // instead of an unhandled 500.
        if (resp.StatusCode == HttpStatusCode.Unauthorized || resp.StatusCode == HttpStatusCode.Forbidden)
        {
            throw new IbkrUnauthorizedException(
                $"IBKR {verb} {path} returned {(int)resp.StatusCode} — no IBKR session (complete the browser login first)");
        }
        if (!resp.IsSuccessStatusCode)
        {
            var body = await SafeReadBodyAsync(resp, ct);
            logger.LogWarning("IBKR {Verb} {Path} returned {Status}: {Body}", verb, path, (int)resp.StatusCode, body);
            resp.EnsureSuccessStatusCode();
        }
        await using var stream = await resp.Content.ReadAsStreamAsync(ct);
        if (stream.Length == 0) return default;
        return await JsonSerializer.DeserializeAsync<T>(stream, JsonOpts, ct);
    }

    private static async Task<string> SafeReadBodyAsync(HttpResponseMessage resp, CancellationToken ct)
    {
        try { return await resp.Content.ReadAsStringAsync(ct); }
        catch { return "<unreadable>"; }
    }

    // ---------- DTOs (private) ---------------------------------------------

    private record AuthStatusDto(bool Authenticated, bool Connected, bool Competing);

    private class TickleResponseDto
    {
        [JsonPropertyName("iserver")]
        public TickleIServerDto? IServer { get; set; }
    }
    private class TickleIServerDto
    {
        [JsonPropertyName("authStatus")]
        public AuthStatusDto? AuthStatus { get; set; }
    }

    private class AccountDto
    {
        [JsonPropertyName("accountId")]
        public string? AccountId { get; set; }
        [JsonPropertyName("currency")]
        public string? Currency { get; set; }
    }

    private class PositionDto
    {
        [JsonPropertyName("conid")]
        public long Conid { get; set; }
        [JsonPropertyName("ticker")]
        public string? Ticker { get; set; }
        [JsonPropertyName("contractDesc")]
        public string? ContractDesc { get; set; }
        [JsonPropertyName("position")]
        public decimal Position { get; set; }
        [JsonPropertyName("avgCost")]
        public decimal AvgCost { get; set; }
        [JsonPropertyName("currency")]
        public string? Currency { get; set; }
        [JsonPropertyName("assetClass")]
        public string? AssetClass { get; set; }
    }

    private class LedgerEntryDto
    {
        [JsonPropertyName("currency")]
        public string? Currency { get; set; }
        [JsonPropertyName("cashbalance")]
        public decimal CashBalance { get; set; }
    }

    private class ContractInfoDto
    {
        [JsonPropertyName("ticker")]
        public string? Ticker { get; set; }
        [JsonPropertyName("symbol")]
        public string? Symbol { get; set; }
        [JsonPropertyName("company_name")]
        public string? CompanyName { get; set; }
    }
}
