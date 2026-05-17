using ShantiSangha.Trading.Services;

namespace ShantiSangha.Trading.Jobs;

/// <summary>
/// Pings the IBKR Client Portal Gateway every 60 seconds to keep the
/// session alive AND to detect when the daily-ish auth window expires.
///
/// `IbkrPortfolioSyncService.KeepaliveAsync` translates the gateway's
/// `/tickle` + `/iserver/auth/status` flags into per-user
/// `IbkrAccount.Status` transitions (Active → NeedsReauth → Disconnected),
/// so the iOS app surfaces the "Re-link IBKR" banner the moment the
/// gateway's cookie stops working.
/// </summary>
public class IbkrSessionKeepaliveJob(IIbkrPortfolioSyncService sync)
{
    public Task RunAsync() => sync.KeepaliveAsync();
}
