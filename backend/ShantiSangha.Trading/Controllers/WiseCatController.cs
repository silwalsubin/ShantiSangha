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

    [HttpGet("history/{ticker}")]
    public async Task<IActionResult> GetHistory(string ticker, int days = 90, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var fromDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-Math.Clamp(days, 1, 400)));
        var bars = await marketData.GetHistoryAsync(ticker, fromDate, ct);
        return Ok(bars);
    }
}
