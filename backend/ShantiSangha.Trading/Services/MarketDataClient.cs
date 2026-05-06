using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Amazon.Lambda;
using Amazon.Lambda.Model;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Trading.Services;

/// <summary>
/// Invokes the wisecat Python Lambda directly via the AWS SDK.
/// Auth = IAM (the ECS task role has lambda:InvokeFunction on this function).
/// </summary>
public class MarketDataClient(
    IAmazonLambda lambda,
    WisecatLambdaConfig config,
    ILogger<MarketDataClient> logger) : IMarketDataClient
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public async Task<IReadOnlyList<MarketBar>> GetHistoryAsync(string ticker, DateOnly fromDate, CancellationToken ct = default)
    {
        var resp = await InvokeAsync<HistoryResponseDto>(new
        {
            action = "history",
            ticker,
            fromDate = fromDate.ToString("yyyy-MM-dd"),
        }, ct);

        if (resp?.Bars is null) return Array.Empty<MarketBar>();
        return resp.Bars
            .Select(b => new MarketBar(DateOnly.Parse(b.Date), b.Open, b.High, b.Low, b.Close, b.Volume))
            .ToList();
    }

    public async Task<QuoteSnapshot?> GetQuoteAsync(string ticker, CancellationToken ct = default)
    {
        var resp = await InvokeAsync<QuoteResponseDto>(new
        {
            action = "quote",
            ticker,
        }, ct);

        if (resp is null || resp.Price is null) return null;
        return new QuoteSnapshot(resp.Ticker, resp.Price.Value, null, null, null);
    }

    public async Task<IReadOnlyList<SymbolMatch>> SearchSymbolsAsync(string query, int limit = 10, CancellationToken ct = default)
    {
        var resp = await InvokeAsync<SymbolSearchResponseDto>(new
        {
            action = "symbolSearch",
            query,
            limit,
        }, ct);

        if (resp?.Results is null) return Array.Empty<SymbolMatch>();
        return resp.Results.Select(r => new SymbolMatch(r.Symbol, r.Description, r.Type)).ToList();
    }

    public async Task<IReadOnlyList<TechnicalScore>> ScoreAsync(IReadOnlyList<ScoreInput> items, CancellationToken ct = default)
    {
        var payload = new
        {
            action = "score",
            items = items.Select(i => new
            {
                ticker = i.Ticker,
                bars = i.Bars.Select(b => new
                {
                    date = b.Date.ToString("yyyy-MM-dd"),
                    open = b.Open,
                    high = b.High,
                    low = b.Low,
                    close = b.Close,
                    volume = b.Volume,
                }).ToList(),
                price = i.Price,
            }).ToList(),
        };

        var resp = await InvokeAsync<ScoreResponseDto>(payload, ct);
        if (resp?.Scores is null) return Array.Empty<TechnicalScore>();
        return resp.Scores.Select(s => new TechnicalScore(
            s.Ticker,
            s.Price,
            s.TechnicalScore,
            (s.Signals ?? new()).Select(c => new TechnicalSignalContribution(c.Name, c.Value, c.Contribution)).ToList()
        )).ToList();
    }

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
            logger.LogWarning(e, "wisecat Lambda invoke failed");
            return default;
        }

        if (!string.IsNullOrEmpty(resp.FunctionError))
        {
            var body = ReadStream(resp.Payload);
            logger.LogWarning("wisecat Lambda returned FunctionError={Error}: {Body}", resp.FunctionError, body);
            return default;
        }

        var responseJson = ReadStream(resp.Payload);
        if (string.IsNullOrEmpty(responseJson)) return default;

        try
        {
            return JsonSerializer.Deserialize<T>(responseJson, JsonOpts);
        }
        catch (JsonException e)
        {
            logger.LogWarning(e, "wisecat response deserialization failed: {Body}", responseJson);
            return default;
        }
    }

    private static string ReadStream(Stream? stream)
    {
        if (stream is null) return string.Empty;
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd();
    }

    // -------- DTOs (match the Lambda handler's wire format) --------

    private record HistoryResponseDto(string Ticker, List<HistoryBarDto>? Bars);
    private record HistoryBarDto(string Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume);

    private record QuoteResponseDto(string Ticker, decimal? Price);

    private record ScoreResponseDto(
        [property: JsonPropertyName("asOf")] string AsOf,
        List<TickerScoreDto>? Scores);

    private record TickerScoreDto(
        string Ticker,
        decimal? Price,
        [property: JsonPropertyName("technicalScore")] double TechnicalScore,
        List<SignalContributionDto>? Signals);

    private record SignalContributionDto(string Name, double Value, double Contribution);

    private record SymbolSearchResponseDto(List<SymbolMatchDto>? Results);
    private record SymbolMatchDto(string Symbol, string Description, string Type);
}

public record WisecatLambdaConfig(string FunctionName);
