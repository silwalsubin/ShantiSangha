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
            .Select(b => new ChartBar(b.Date, b.Open, b.High, b.Low, b.Close, b.Volume, b.ExtendedHours))
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
            ToHorizonScore(s, "1W"),
            ToHorizonScore(s, "1M"),
            ToHorizonScore(s, "1Y")
        )).ToList();
    }

    private static HorizonTechnicalScore ToHorizonScore(TickerScoreDto dto, string horizon)
    {
        // Lambda returns horizons keyed "1W"/"1M"/"1Y". If a key is missing
        // (e.g. older Lambda revision still in flight), fall back to the
        // legacy top-level signals so the consumer doesn't see all-zeros.
        //
        // The GBM classifier fields (pBuy/pHold/pSell/expectedReturn) may
        // also be absent on older Lambda revisions — when missing we default
        // pHold=1 (fully Hold) and the rest to 0 so the verdict reads
        // unambiguously instead of as a 0/0/0 probability triple.
        if (dto.Horizons is { } horizons && horizons.TryGetValue(horizon, out var h) && h is not null)
        {
            var contribs = (h.Signals ?? new())
                .Select(c => new TechnicalSignalContribution(c.Name, c.Value, c.Contribution, c.Weight))
                .ToList();
            return new HorizonTechnicalScore(
                h.Score,
                h.PBuy ?? 0.0,
                h.PHold ?? 1.0,
                h.PSell ?? 0.0,
                h.ExpectedReturn ?? 0.0,
                contribs);
        }
        // Fallback: legacy shape — apply only for 1M (the legacy default horizon).
        if (horizon == "1M")
        {
            var contribs = (dto.Signals ?? new())
                .Select(c => new TechnicalSignalContribution(c.Name, c.Value, c.Contribution, c.Weight))
                .ToList();
            return new HorizonTechnicalScore(
                dto.TechnicalScore,
                PBuy: 0.0,
                PHold: 1.0,
                PSell: 0.0,
                ExpectedReturn: 0.0,
                contribs);
        }
        return new HorizonTechnicalScore(
            Score: 0.0,
            PBuy: 0.0,
            PHold: 1.0,
            PSell: 0.0,
            ExpectedReturn: 0.0,
            Contributions: Array.Empty<TechnicalSignalContribution>());
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
        List<SignalContributionDto>? Signals,
        Dictionary<string, HorizonScoreDto>? Horizons);

    // PBuy / PHold / PSell / ExpectedReturn arrive once the Python Lambda is
    // upgraded to emit GBM probabilities; until then they're absent on the
    // wire and deserialize as null. Caller substitutes the neutral default
    // (pHold=1, others 0).
    private record HorizonScoreDto(
        double Score,
        List<SignalContributionDto>? Signals,
        [property: JsonPropertyName("pBuy")] double? PBuy,
        [property: JsonPropertyName("pHold")] double? PHold,
        [property: JsonPropertyName("pSell")] double? PSell,
        [property: JsonPropertyName("expectedReturn")] double? ExpectedReturn);

    private record SignalContributionDto(string Name, double Value, double Contribution, double Weight);

    private record SymbolSearchResponseDto(List<SymbolMatchDto>? Results);
    private record SymbolMatchDto(string Symbol, string Description, string Type);

    private record ChartHistoryResponseDto(
        string Ticker,
        string Period,
        List<ChartBarDto>? Bars,
        ChartAggregatesDto? Aggregates);

    private record ChartBarDto(string Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume, bool? ExtendedHours);

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
