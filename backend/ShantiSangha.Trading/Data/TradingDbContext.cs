using Microsoft.EntityFrameworkCore;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Data;

public class TradingDbContext(DbContextOptions<TradingDbContext> options) : DbContext(options)
{
    public DbSet<WatchlistItem> WatchlistItems => Set<WatchlistItem>();
    public DbSet<TickerDailyClose> TickerDailyCloses => Set<TickerDailyClose>();
    public DbSet<TradingSignal> TradingSignals => Set<TradingSignal>();
    public DbSet<UserPortfolioPosition> UserPortfolioPositions => Set<UserPortfolioPosition>();
    public DbSet<TickerSector> TickerSectors => Set<TickerSector>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<WatchlistItem>(e =>
        {
            e.HasKey(w => w.Id);
            e.HasIndex(w => w.UserId);
            e.HasIndex(w => new { w.UserId, w.Ticker }).IsUnique();
            e.Property(w => w.Ticker).HasMaxLength(16).IsRequired();
        });

        modelBuilder.Entity<TickerDailyClose>(e =>
        {
            e.HasKey(b => new { b.Ticker, b.Date });
            e.Property(b => b.Ticker).HasMaxLength(16).IsRequired();
            e.Property(b => b.Open).HasPrecision(18, 4);
            e.Property(b => b.High).HasPrecision(18, 4);
            e.Property(b => b.Low).HasPrecision(18, 4);
            e.Property(b => b.Close).HasPrecision(18, 4);
        });

        modelBuilder.Entity<TradingSignal>(e =>
        {
            e.HasKey(s => s.Id);
            e.HasIndex(s => new { s.UserId, s.Date });
            e.HasIndex(s => new { s.UserId, s.Ticker, s.Date }).IsUnique();
            e.Property(s => s.Ticker).HasMaxLength(16).IsRequired();
            e.Property(s => s.Action1W).HasConversion<string>().HasMaxLength(8);
            e.Property(s => s.Action1M).HasConversion<string>().HasMaxLength(8);
            e.Property(s => s.Action1Y).HasConversion<string>().HasMaxLength(8);
            e.Property(s => s.PriceAtSignal).HasPrecision(18, 4);
            e.Property(s => s.ReasoningJson).HasColumnType("jsonb");
        });

        modelBuilder.Entity<UserPortfolioPosition>(e =>
        {
            e.HasKey(p => p.Id);
            e.HasIndex(p => p.UserId);
            e.HasIndex(p => new { p.UserId, p.Ticker }).IsUnique();
            e.Property(p => p.Ticker).HasMaxLength(16).IsRequired();
            e.Property(p => p.Shares).HasPrecision(18, 6);
            e.Property(p => p.CostBasis).HasPrecision(18, 4);
        });

        modelBuilder.Entity<TickerSector>(e =>
        {
            e.HasKey(t => t.Ticker);
            e.Property(t => t.Ticker).HasMaxLength(16);
            e.Property(t => t.Sector).HasMaxLength(64).IsRequired();
            e.Property(t => t.Name).HasMaxLength(256);
        });
    }
}
