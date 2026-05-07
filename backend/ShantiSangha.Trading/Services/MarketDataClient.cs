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

    public async Task<ChartHistoryResult?> GetChartHistoryAsync(string ticker, string period, CancellationToken ct = default)
    {
        var resp = await InvokeAsync<ChartHistoryResponseDto>(new
        {
            action = "chartHistory",
            ticker,
            period,
        }, ct);

        if (resp is null) return null;
        var bars = (resp.Bars ?? new())
            .Select(b => new ChartBar(b.Date, b.Open, b.High, b.Low, b.Close, b.Volume))
            .ToList();
        ChartAggregates? agg = null;
        if (resp.Aggregates is { } a)
        {
            agg = new ChartAggregates(
                a.CurrentPrice,
                a.PreviousClose,
                a.WeekHigh52,
                a.WeekLow52,
                a.AllTimeHigh,
                a.AllTimeLow,
                DateOnly.Parse(a.FirstDate),
                DateOnly.Parse(a.LatestDate)
            );
        }
        return new ChartHistoryResult(resp.Ticker, resp.Period, bars, agg);
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
            (s.Signals ?? new()).Select(c => new TechnicalSignalContribution(c.Name, c.Value, c.Contribution, c.Weight)).ToList()
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

    private record SignalContributionDto(string Name, double Value, double Contribution, double Weight);

    private record SymbolSearchResponseDto(List<SymbolMatchDto>? Results);
    private record SymbolMatchDto(string Symbol, string Description, string Type);

    private record ChartHistoryResponseDto(
        string Ticker,
        string Period,
        List<ChartBarDto>? Bars,
        ChartAggregatesDto? Aggregates);

    private record ChartBarDto(string Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume);

    private record ChartAggregatesDto(
        [property: JsonPropertyName("currentPrice")] decimal CurrentPrice,
        [property: JsonPropertyName("previousClose")] decimal? PreviousClose,
        [property: JsonPropertyName("weekHigh52")] decimal? WeekHigh52,
        [property: JsonPropertyName("weekLow52")] decimal? WeekLow52,
        [property: JsonPropertyName("allTimeHigh")] decimal AllTimeHigh,
        [property: JsonPropertyName("allTimeLow")] decimal AllTimeLow,
        [property: JsonPropertyName("firstDate")] string FirstDate,
        [property: JsonPropertyName("latestDate")] string LatestDate);
}

public record WisecatLambdaConfig(string FunctionName);
