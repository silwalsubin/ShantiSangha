namespace ShantiSangha.Trading.Models;

public enum IbkrAccountStatus
{
    Disconnected = 0,
    Active = 1,
    NeedsReauth = 2,
    Suspended = 3,
}

public class IbkrAccount
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string IbkrAccountId { get; set; } = string.Empty;
    public IbkrAccountStatus Status { get; set; } = IbkrAccountStatus.Disconnected;

    public DateTime LinkedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastSyncAt { get; set; }
    public DateTime? LastSuccessfulSyncAt { get; set; }
    public string? LastErrorMessage { get; set; }
    public DateTime? LastErrorAt { get; set; }

    public string BaseCurrency { get; set; } = "USD";
    public decimal CashBalance { get; set; }
    public DateTime? CashBalanceAt { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
