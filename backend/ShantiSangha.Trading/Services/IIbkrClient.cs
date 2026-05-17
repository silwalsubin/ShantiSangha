namespace ShantiSangha.Trading.Services;

/// <summary>
/// Snapshot of `/iserver/auth/status` from the IBKR Client Portal Gateway.
/// `Authenticated` flips to false after ~24h or on a server-side logout;
/// when that happens, every other endpoint will start returning 401.
/// </summary>
public record IbkrAuthStatus(bool Authenticated, bool Connected, bool Competing);

/// <summary>
/// One row from `/portfolio/{acctId}/positions/0`. The IBKR API surfaces a
/// lot more fields (markPrice, marketValue, etc.) but we only mirror what
/// we actually persist. Negative `Position` = short — filtered out by the
/// sync service for v1.
/// </summary>
public record IbkrPosition(
    long Conid,
    string? Ticker,
    string? ContractDesc,
    decimal Position,
    decimal AvgCost,
    string Currency,
    string AssetClass
);

/// <summary>
/// Subset of `/portfolio/{acctId}/ledger` — we only care about the base
/// currency row (`BASE` or the explicit currency code). Cash balance is the
/// `cashbalance` field, settled cash available for new positions.
/// </summary>
public record IbkrLedgerEntry(string Currency, decimal CashBalance);

/// <summary>
/// One account from `/portfolio/accounts`. The list endpoint MUST be hit
/// once after the session is established before any per-account call works
/// (IBKR caches the account list inside the gateway process).
/// </summary>
public record IbkrAccountSummary(string AccountId, string? Currency);

/// <summary>
/// Minimal contract-info row from `/iserver/contract/{conid}/info`. Used
/// only as a fallback when a position row arrives without a ticker.
/// </summary>
public record IbkrContractInfo(long Conid, string? Ticker, string? CompanyName);

/// <summary>
/// Typed wrapper around the IBKR Client Portal Gateway REST API. The
/// gateway is a Java sidecar listening on http://localhost:5000 (HTTPS
/// with a self-signed cert in real deployments). Auth is session-cookie
/// based — interactive 2FA login required ~daily.
/// </summary>
public interface IIbkrClient
{
    Task<IbkrAuthStatus> GetAuthStatusAsync(CancellationToken ct = default);

    /// <summary>POST /tickle — keepalive ping. Returns the auth status.</summary>
    Task<IbkrAuthStatus> TickleAsync(CancellationToken ct = default);

    /// <summary>
    /// GET /portfolio/accounts — REQUIRED once per session before any
    /// `/portfolio/{acctId}/*` call. The gateway caches the response.
    /// </summary>
    Task<IReadOnlyList<IbkrAccountSummary>> GetAccountsAsync(CancellationToken ct = default);

    Task<IReadOnlyList<IbkrPosition>> GetPositionsAsync(string accountId, CancellationToken ct = default);

    Task<IReadOnlyList<IbkrLedgerEntry>> GetLedgerAsync(string accountId, CancellationToken ct = default);

    Task<IbkrContractInfo?> ResolveContractAsync(long conid, CancellationToken ct = default);
}

/// <summary>
/// Raised when the gateway answers 401 or `authenticated:false`. The sync
/// service catches this and flips IbkrAccount.Status to NeedsReauth.
/// </summary>
public class IbkrUnauthorizedException : Exception
{
    public IbkrUnauthorizedException(string message) : base(message) { }
}
