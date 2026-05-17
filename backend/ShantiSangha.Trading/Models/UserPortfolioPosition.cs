namespace ShantiSangha.Trading.Models;

public enum PositionSource
{
    Manual = 0,
    Ibkr = 1,
}

public class UserPortfolioPosition
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Ticker { get; set; } = string.Empty;
    public decimal Shares { get; set; }
    public decimal CostBasis { get; set; }  // per share
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Broker linkage — populated when Source = Ibkr. Manual rows leave these null.
    public PositionSource Source { get; set; } = PositionSource.Manual;
    public string? ExternalAccountId { get; set; }
    public string? ExternalPositionId { get; set; }
    public long? Conid { get; set; }
}
