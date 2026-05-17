using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;
using ShantiSangha.Trading.Services;

namespace ShantiSangha.Trading.Jobs;

/// <summary>
/// Pulls fresh positions + cash from IBKR for every linked user. Cron'd
/// every 15 minutes during US market hours (`*/15 13-21 * * 1-5` UTC).
///
/// Failures per-user are isolated — one user's OAuth expiry doesn't stop
/// the loop for other linked accounts. Each failure flips that user's
/// IbkrAccount.Status appropriately (NeedsReauth on 401, otherwise the
/// existing status is kept and LastErrorMessage is updated).
/// </summary>
public class IbkrPortfolioSyncJob(
    TradingDbContext db,
    IIbkrPortfolioSyncService sync,
    ILogger<IbkrPortfolioSyncJob> logger)
{
    public async Task RunAsync()
    {
        var linked = await db.IbkrAccounts
            .Where(a => a.Status == IbkrAccountStatus.Active)
            .Select(a => a.UserId)
            .ToListAsync();

        var ok = 0;
        var failed = 0;
        foreach (var userId in linked)
        {
            try
            {
                var result = await sync.SyncAsync(userId);
                if (result.Success) ok++;
                else failed++;
            }
            catch (Exception e)
            {
                failed++;
                logger.LogWarning(e, "Scheduled IBKR sync failed for {UserId}", userId);
            }
        }

        logger.LogInformation(
            "IbkrPortfolioSyncJob: {Ok} synced, {Failed} failed ({Total} linked accounts)",
            ok, failed, linked.Count);
    }
}
