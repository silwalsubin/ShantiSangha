using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Trading.Contracts;
using ShantiSangha.Trading.Services;

namespace ShantiSangha.Trading.Controllers;

[ApiController]
[Authorize]
[Route("api/wisecat")]
public class WiseCatController(
    IWatchlistService watchlist,
    ITradingSignalService signals,
    IMarketDataClient marketData,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet("watchlist")]
    public async Task<IActionResult> GetWatchlist(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var items = await watchlist.ListAsync(user.Id, ct);
        return Ok(items);
    }

    [HttpPost("watchlist")]
    public async Task<IActionResult> AddWatchlist([FromBody] AddWatchlistRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var item = await watchlist.AddAsync(user.Id, body.Ticker, ct);
            return Ok(item);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpDelete("watchlist/{ticker}")]
    public async Task<IActionResult> RemoveWatchlist(string ticker, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var removed = await watchlist.RemoveAsync(user.Id, ticker, ct);
        return removed ? NoContent() : NotFound();
    }

    [HttpGet("signals")]
    public async Task<IActionResult> GetSignals(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var items = await signals.GetTodayAsync(user.Id, ct);
        return Ok(items);
    }

    [HttpGet("signals/{ticker}")]
    public async Task<IActionResult> GetSignal(string ticker, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var dto = await signals.GenerateAsync(user.Id, ticker, today, ct);
        return dto is null ? NotFound() : Ok(dto);
    }

    [HttpGet("symbols/search")]
    public async Task<IActionResult> SearchSymbols(string q, int limit = 10, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var trimmed = (q ?? string.Empty).Trim();
        if (trimmed.Length < 1) return Ok(Array.Empty<object>());

        var results = await marketData.SearchSymbolsAsync(trimmed, Math.Clamp(limit, 1, 25), ct);
        return Ok(results);
    }

    [HttpGet("history/{ticker}")]
    public async Task<IActionResult> GetHistory(string ticker, int days = 90, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var fromDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-Math.Clamp(days, 1, 400)));
        var bars = await marketData.GetHistoryAsync(ticker, fromDate, ct);
        return Ok(bars);
    }

    [HttpGet("chart/{ticker}")]
    public async Task<IActionResult> GetChart(string ticker, string period = "1y", CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var validPeriods = new HashSet<string> { "1mo", "6mo", "1y", "5y", "max" };
        var normalized = period.ToLowerInvariant();
        if (!validPeriods.Contains(normalized))
            return BadRequest(new { error = $"period must be one of: {string.Join(", ", validPeriods)}" });

        var result = await marketData.GetChartHistoryAsync(ticker, normalized, ct);
        return result is null ? NotFound() : Ok(result);
    }
}
