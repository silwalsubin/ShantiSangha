using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Trading.Services;

public class MarketDataClient(IHttpClientFactory httpClientFactory, ILogger<MarketDataClient> logger) : IMarketDataClient
{
    public const string HttpClientName = "WiseCatPy";

    public async Task<IReadOnlyList<MarketBar>> GetHistoryAsync(string ticker, DateOnly fromDate, CancellationToken ct = default)
    {
        var http = httpClientFactory.CreateClient(HttpClientName);
        var url = $"/history/{Uri.EscapeDataString(ticker)}?from_date={fromDate:yyyy-MM-dd}";
        var resp = await http.GetAsync(url, ct);
        if (!resp.IsSuccessStatusCode)
        {
            logger.LogWarning("wisecat /history {Ticker} failed: {Status}", ticker, resp.StatusCode);
            return Array.Empty<MarketBar>();
        }
        var body = await resp.Content.ReadFromJsonAsync<HistoryResponseDto>(cancellationToken: ct);
        if (body?.Bars is null) return Array.Empty<MarketBar>();
        return body.Bars
            .Select(b => new MarketBar(DateOnly.Parse(b.Date), b.Open, b.High, b.Low, b.Close, b.Volume))
            .ToList();
    }

    public async Task<QuoteSnapshot?> GetQuoteAsync(string ticker, CancellationToken ct = default)
    {
        var http = httpClientFactory.CreateClient(HttpClientName);
        var resp = await http.GetAsync($"/quote/{Uri.EscapeDataString(ticker)}", ct);
        if (!resp.IsSuccessStatusCode) return null;
        var body = await resp.Content.ReadFromJsonAsync<QuoteResponseDto>(cancellationToken: ct);
        if (body is null) return null;
        return new QuoteSnapshot(body.Ticker, body.Price, null, null, null);
    }

    public async Task<IReadOnlyList<TechnicalScore>> ScoreAsync(IReadOnlyList<ScoreInput> items, CancellationToken ct = default)
    {
        var http = httpClientFactory.CreateClient(HttpClientName);
        var body = new ScoreRequestDto(items.Select(i => new ScoreItemDto(
            i.Ticker,
            i.Bars.Select(b => new BarDto(b.Date.ToString("yyyy-MM-dd"), b.Open, b.High, b.Low, b.Close, b.Volume)).ToList(),
            i.Price
        )).ToList());

        var resp = await http.PostAsJsonAsync("/score", body, ct);
        if (!resp.IsSuccessStatusCode)
        {
            logger.LogWarning("wisecat /score failed: {Status}", resp.StatusCode);
            return Array.Empty<TechnicalScore>();
        }
        var parsed = await resp.Content.ReadFromJsonAsync<ScoreResponseDto>(cancellationToken: ct);
        if (parsed?.Scores is null) return Array.Empty<TechnicalScore>();
        return parsed.Scores.Select(s => new TechnicalScore(
            s.Ticker,
            s.Price,
            s.TechnicalScore,
            s.Signals.Select(c => new TechnicalSignalContribution(c.Name, c.Value, c.Contribution)).ToList()
        )).ToList();
    }

    // -------- DTOs (match the Python service's wire format) --------

    private record HistoryResponseDto(string Ticker, List<HistoryBarDto> Bars);
    private record HistoryBarDto(string Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume);

    private record QuoteResponseDto(string Ticker, decimal Price);

    private record ScoreRequestDto(List<ScoreItemDto> Items);
    private record ScoreItemDto(string Ticker, List<BarDto> Bars, decimal? Price);
    private record BarDto(string Date, decimal Open, decimal High, decimal Low, decimal Close, long Volume);

    private record ScoreResponseDto(
        [property: JsonPropertyName("asOf")] string AsOf,
        List<TickerScoreDto> Scores);

    private record TickerScoreDto(
        string Ticker,
        decimal? Price,
        [property: JsonPropertyName("technicalScore")] double TechnicalScore,
        List<SignalContributionDto> Signals);

    private record SignalContributionDto(string Name, double Value, double Contribution);
}
