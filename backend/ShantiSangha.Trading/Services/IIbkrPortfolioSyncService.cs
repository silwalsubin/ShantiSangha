using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public record IbkrSyncResult(
    bool Success,
    int PositionsImported,
    int PositionsSkipped,
    decimal CashBalance,
    string BaseCurrency,
    IbkrAccountStatus Status,
    string? ErrorMessage
);

public interface IIbkrPortfolioSyncService
{
    /// <summary>
    /// Initial link — discovers the user's IBKR account via the gateway,
    /// creates the IbkrAccount row, wipes any manual UserPortfolioPosition
    /// rows, and runs a first sync.
    /// </summary>
    Task<IbkrSyncResult> LinkAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Pull positions + ledger from IBKR and replace the user's
    /// UserPortfolioPosition rows. Idempotent. Called by the scheduled job
    /// and by the resync endpoint.
    /// </summary>
    Task<IbkrSyncResult> SyncAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Refresh only if `LastSuccessfulSyncAt` is older than `maxAge`. Errors
    /// are swallowed (logged) — callers want to render plan data even when
    /// the broker is briefly unreachable.
    /// </summary>
    Task RefreshIfStaleAsync(Guid userId, TimeSpan maxAge, CancellationToken ct = default);

    /// <summary>
    /// Soft disconnect — flips Status to Disconnected, preserves position
    /// rows so the iOS app can fall back to "last known" view. Manual edits
    /// re-enabled.
    /// </summary>
    Task UnlinkAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Run keepalive against the gateway and translate the auth flags into
    /// `IbkrAccount.Status` for every linked user. Called by the Hangfire
    /// keepalive job every 60s.
    /// </summary>
    Task KeepaliveAsync(CancellationToken ct = default);
}
