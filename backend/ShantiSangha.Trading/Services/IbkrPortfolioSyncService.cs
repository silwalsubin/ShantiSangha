using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public class IbkrPortfolioSyncService(
    TradingDbContext db,
    IIbkrClient ibkr,
    ILogger<IbkrPortfolioSyncService> logger) : IIbkrPortfolioSyncService
{
    // Symbol normalization — IBKR uses space-separated share-class suffixes
    // ("BRK B"), our market data layer uses dashes ("BRK-B").
    private static readonly Dictionary<string, string> TickerAliases =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["BRK B"] = "BRK-B",
            ["BRK A"] = "BRK-A",
            ["BF B"]  = "BF-B",
            ["BF A"]  = "BF-A",
        };

    public async Task<IbkrSyncResult> LinkAsync(Guid userId, CancellationToken ct = default)
    {
        var account = await db.IbkrAccounts.FirstOrDefaultAsync(a => a.UserId == userId, ct);
        if (account is null)
        {
            // Look up the IBKR account number via the gateway (must be
            // authed first — caller is expected to have completed the 2FA
            // flow before hitting Link).
            IReadOnlyList<IbkrAccountSummary> accounts;
            try
            {
                accounts = await ibkr.GetAccountsAsync(ct);
            }
            catch (IbkrUnauthorizedException)
            {
                throw new InvalidOperationException(
                    "IBKR gateway is not authenticated. Complete the login flow first.");
            }
            if (accounts.Count == 0)
            {
                throw new InvalidOperationException("IBKR returned no accounts for this session.");
            }
            var primary = accounts[0];
            account = new IbkrAccount
            {
                UserId = userId,
                IbkrAccountId = primary.AccountId,
                BaseCurrency = primary.Currency ?? "USD",
                Status = IbkrAccountStatus.Active,
                LinkedAt = DateTime.UtcNow,
            };
            db.IbkrAccounts.Add(account);
            await db.SaveChangesAsync(ct);
        }

        return await SyncInternalAsync(account, isInitialLink: true, ct);
    }

    public async Task<IbkrSyncResult> SyncAsync(Guid userId, CancellationToken ct = default)
    {
        var account = await db.IbkrAccounts.FirstOrDefaultAsync(a => a.UserId == userId, ct)
            ?? throw new InvalidOperationException("IBKR account not linked for this user.");
        return await SyncInternalAsync(account, isInitialLink: false, ct);
    }

    public async Task RefreshIfStaleAsync(Guid userId, TimeSpan maxAge, CancellationToken ct = default)
    {
        var account = await db.IbkrAccounts.FirstOrDefaultAsync(a => a.UserId == userId, ct);
        if (account is null) return;
        if (account.Status != IbkrAccountStatus.Active) return;
        if (account.LastSuccessfulSyncAt is { } last && DateTime.UtcNow - last < maxAge) return;

        try
        {
            await SyncInternalAsync(account, isInitialLink: false, ct);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "Lazy IBKR refresh failed for {UserId}; serving stale data", userId);
        }
    }

    public async Task UnlinkAsync(Guid userId, CancellationToken ct = default)
    {
        var account = await db.IbkrAccounts.FirstOrDefaultAsync(a => a.UserId == userId, ct);
        if (account is null) return;
        account.Status = IbkrAccountStatus.Disconnected;
        account.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    public async Task KeepaliveAsync(CancellationToken ct = default)
    {
        IbkrAuthStatus auth;
        try
        {
            auth = await ibkr.TickleAsync(ct);
        }
        catch (Exception e)
        {
            logger.LogWarning(e, "IBKR keepaliveTickle failed — gateway likely down");
            await MarkAllLinkedAsync(IbkrAccountStatus.Disconnected, "Gateway unreachable", ct);
            return;
        }

        // The gateway is shared across users (v1 = single user anyway), so
        // we flip every linked account to the same status. If multi-user
        // support lands later, we'll need a per-user session.
        var target = auth.Authenticated
            ? IbkrAccountStatus.Active
            : IbkrAccountStatus.NeedsReauth;
        await MarkAllLinkedAsync(target, auth.Authenticated ? null : "Session expired", ct);
    }

    // ---------- core sync --------------------------------------------------

    private async Task<IbkrSyncResult> SyncInternalAsync(IbkrAccount account, bool isInitialLink, CancellationToken ct)
    {
        account.LastSyncAt = DateTime.UtcNow;
        try
        {
            // IBKR requires /portfolio/accounts before /portfolio/{acct}/* —
            // the gateway lazy-loads account state on that first call.
            await ibkr.GetAccountsAsync(ct);

            var positionsTask = ibkr.GetPositionsAsync(account.IbkrAccountId, ct);
            var ledgerTask = ibkr.GetLedgerAsync(account.IbkrAccountId, ct);
            await Task.WhenAll(positionsTask, ledgerTask);

            var rawPositions = positionsTask.Result;
            var ledger = ledgerTask.Result;

            // Stale-session zero-positions guard: IBKR has a known quirk where
            // an expiring session returns 200 + [] before flipping to 401. If
            // we wipe the local table on that response, the user loses their
            // (real) holdings until next sync. So: if the API returned zero
            // positions AND we have local rows AND auth status is suspicious,
            // refuse to write.
            var cachedCount = await db.UserPortfolioPositions
                .CountAsync(p => p.UserId == account.UserId, ct);
            if (rawPositions.Count == 0 && cachedCount > 0)
            {
                var authStatus = await ibkr.GetAuthStatusAsync(ct);
                if (!authStatus.Authenticated || ledger.Count == 0)
                {
                    return await FailAsync(account,
                        "IBKR returned 0 positions but session looks stale — refusing to wipe local data.",
                        IbkrAccountStatus.NeedsReauth, ct);
                }
            }

            var (clean, skipped) = FilterAndNormalize(rawPositions, account.BaseCurrency);

            // Replace UserPortfolioPositions for this user atomically.
            var existing = await db.UserPortfolioPositions
                .Where(p => p.UserId == account.UserId)
                .ToListAsync(ct);
            db.UserPortfolioPositions.RemoveRange(existing);

            var now = DateTime.UtcNow;
            foreach (var p in clean)
            {
                db.UserPortfolioPositions.Add(new UserPortfolioPosition
                {
                    UserId = account.UserId,
                    Ticker = p.Ticker,
                    Shares = p.Shares,
                    CostBasis = p.CostBasis,
                    Source = PositionSource.Ibkr,
                    ExternalAccountId = account.IbkrAccountId,
                    ExternalPositionId = p.Conid.ToString(),
                    Conid = p.Conid,
                    CreatedAt = now,
                    UpdatedAt = now,
                });
            }

            // Cash — find the row matching the account's base currency.
            var baseRow = ledger.FirstOrDefault(l =>
                string.Equals(l.Currency, account.BaseCurrency, StringComparison.OrdinalIgnoreCase));
            if (baseRow is not null)
            {
                account.CashBalance = baseRow.CashBalance;
                account.CashBalanceAt = now;
            }

            account.Status = IbkrAccountStatus.Active;
            account.LastSuccessfulSyncAt = now;
            account.LastErrorMessage = null;
            account.LastErrorAt = null;
            account.UpdatedAt = now;
            await db.SaveChangesAsync(ct);

            logger.LogInformation(
                "IBKR sync ok for user {UserId}: {Imported} positions imported, {Skipped} skipped, cash {Cash} {Currency}",
                account.UserId, clean.Count, skipped, account.CashBalance, account.BaseCurrency);

            return new IbkrSyncResult(
                Success: true,
                PositionsImported: clean.Count,
                PositionsSkipped: skipped,
                CashBalance: account.CashBalance,
                BaseCurrency: account.BaseCurrency,
                Status: account.Status,
                ErrorMessage: null);
        }
        catch (IbkrUnauthorizedException e)
        {
            return await FailAsync(account, e.Message, IbkrAccountStatus.NeedsReauth, ct);
        }
        catch (Exception e)
        {
            logger.LogError(e, "IBKR sync failed for user {UserId}", account.UserId);
            return await FailAsync(account, e.Message, account.Status, ct);
        }
    }

    private async Task<IbkrSyncResult> FailAsync(IbkrAccount account, string message, IbkrAccountStatus newStatus, CancellationToken ct)
    {
        account.Status = newStatus;
        account.LastErrorMessage = message.Length > 512 ? message[..512] : message;
        account.LastErrorAt = DateTime.UtcNow;
        account.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return new IbkrSyncResult(
            Success: false,
            PositionsImported: 0,
            PositionsSkipped: 0,
            CashBalance: account.CashBalance,
            BaseCurrency: account.BaseCurrency,
            Status: account.Status,
            ErrorMessage: message);
    }

    private async Task MarkAllLinkedAsync(IbkrAccountStatus status, string? errorMessage, CancellationToken ct)
    {
        var rows = await db.IbkrAccounts
            .Where(a => a.Status != IbkrAccountStatus.Disconnected)
            .ToListAsync(ct);
        if (rows.Count == 0) return;
        var now = DateTime.UtcNow;
        foreach (var r in rows)
        {
            if (r.Status == status) continue;
            r.Status = status;
            r.UpdatedAt = now;
            if (errorMessage is not null)
            {
                r.LastErrorMessage = errorMessage;
                r.LastErrorAt = now;
            }
        }
        await db.SaveChangesAsync(ct);
    }

    private record CleanPosition(string Ticker, decimal Shares, decimal CostBasis, long Conid);

    private static (List<CleanPosition> Clean, int Skipped) FilterAndNormalize(
        IReadOnlyList<IbkrPosition> rows, string baseCurrency)
    {
        var clean = new List<CleanPosition>();
        var skipped = 0;
        foreach (var r in rows)
        {
            // v1 filters: stocks only, base currency only, longs only.
            if (!string.Equals(r.AssetClass, "STK", StringComparison.OrdinalIgnoreCase))
            {
                skipped++;
                continue;
            }
            if (!string.Equals(r.Currency, baseCurrency, StringComparison.OrdinalIgnoreCase))
            {
                skipped++;
                continue;
            }
            if (r.Position <= 0)
            {
                skipped++;
                continue;
            }
            var ticker = ResolveTicker(r);
            if (string.IsNullOrEmpty(ticker))
            {
                skipped++;
                continue;
            }
            clean.Add(new CleanPosition(ticker, r.Position, r.AvgCost, r.Conid));
        }
        return (clean, skipped);
    }

    private static string ResolveTicker(IbkrPosition r)
    {
        var raw = r.Ticker;
        if (string.IsNullOrWhiteSpace(raw))
        {
            // ContractDesc usually starts with the ticker, e.g. "AAPL"
            // or "BRK B - BERKSHIRE HATHAWAY". Take the first token.
            var desc = r.ContractDesc ?? string.Empty;
            var firstSpace = desc.IndexOf(' ');
            raw = firstSpace > 0 ? desc[..firstSpace] : desc;
        }
        raw = raw.Trim().ToUpperInvariant();
        if (TickerAliases.TryGetValue(raw, out var aliased)) return aliased;
        return raw;
    }
}
