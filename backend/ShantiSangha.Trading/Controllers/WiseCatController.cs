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
    IPortfolioService portfolio,
    IStrategySettingsService strategySettings,
    IJournalService journal,
    IStrategyBacktestService backtest,
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

    /// <summary>
    /// Enriched symbol search — adds sector (cache-only resolution) and
    /// p_buy / p_sell at the user's entry horizon (scored from cached bars
    /// only). Powers the in-app search bar's filter chips + signal badges.
    /// </summary>
    [HttpGet("symbols/search/enriched")]
    public async Task<IActionResult> SearchSymbolsEnriched(string q, int limit = 12, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var rows = await portfolio.SearchEnrichedAsync(user.Id, q ?? string.Empty, limit, ct);
        return Ok(rows);
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

        var validPeriods = new HashSet<string> { "1d", "1w", "1mo", "3mo", "ytd", "1y", "5y", "max" };
        var normalized = period.ToLowerInvariant();
        if (!validPeriods.Contains(normalized))
            return BadRequest(new { error = $"period must be one of: {string.Join(", ", validPeriods)}" });

        var result = await marketData.GetChartHistoryAsync(ticker, normalized, ct);
        return result is null ? NotFound() : Ok(result);
    }

    // ---------- Portfolio (Mode B strategy support) -------------------------

    [HttpGet("portfolio")]
    public async Task<IActionResult> GetPortfolio(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var items = await portfolio.ListAsync(user.Id, ct);
        return Ok(items);
    }

    [HttpPost("portfolio")]
    public async Task<IActionResult> SavePortfolio([FromBody] SavePortfolioRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var positions = body?.Positions ?? Array.Empty<SavePortfolioPosition>();
            var saved = await portfolio.ReplaceAsync(user.Id, positions, ct);
            return Ok(saved);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("portfolio/plan")]
    public async Task<IActionResult> GetPortfolioPlan([FromQuery] decimal? cash = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var plan = await portfolio.GeneratePlanAsync(user.Id, cash, ct);
        return Ok(plan);
    }

    [HttpPost("portfolio/position")]
    public async Task<IActionResult> AddPortfolioPosition([FromBody] SavePortfolioPosition body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var added = await portfolio.AddAsync(user.Id, body, ct);
            return Ok(added);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpDelete("portfolio/position/{ticker}")]
    public async Task<IActionResult> RemovePortfolioPosition(string ticker, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var removed = await portfolio.RemoveAsync(user.Id, ticker, ct);
        return removed ? NoContent() : NotFound();
    }

    // ---------- Strategy settings (Rule constants per user) ----------------

    [HttpGet("strategy/settings")]
    public async Task<IActionResult> GetStrategySettings(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var row = await strategySettings.GetOrCreateAsync(user.Id, ct);
        return Ok(ToDto(row));
    }

    [HttpPut("strategy/settings")]
    public async Task<IActionResult> UpdateStrategySettings(
        [FromBody] UpdateStrategySettingsRequest body,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var row = await strategySettings.UpdateAsync(user.Id, body, ct);
            return Ok(ToDto(row));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // ---------- Journal (Rule 8) -------------------------------------------

    [HttpGet("journal")]
    public async Task<IActionResult> GetJournal([FromQuery] int limit = 50, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var rows = await journal.ListAsync(user.Id, limit, ct);
        return Ok(rows);
    }

    [HttpPost("journal")]
    public async Task<IActionResult> AddJournal([FromBody] CreateJournalEntryRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var row = await journal.CreateAsync(user.Id, body, ct);
            return Ok(row);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpDelete("journal/{id:guid}")]
    public async Task<IActionResult> DeleteJournal(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var ok = await journal.DeleteAsync(user.Id, id, ct);
        return ok ? NoContent() : NotFound();
    }

    // ---------- Backtest preview (Rules-sheet button) ----------------------

    [HttpPost("strategy/backtest")]
    public async Task<IActionResult> RunStrategyBacktest(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var result = await backtest.RunAsync(user.Id, ct);
        return Ok(result);
    }

    private static StrategySettingsDto ToDto(ShantiSangha.Trading.Models.UserStrategySettings r) =>
        new(r.StopLossPct, r.TakeProfitPct, r.EntryThresholdPBuy, r.EntryHorizon,
            r.CooldownDays, r.PositionCapPct, r.MinSectors, r.SellSignalPSell, r.UpdatedAt);
}
