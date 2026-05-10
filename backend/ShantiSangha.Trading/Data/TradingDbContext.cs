using Microsoft.EntityFrameworkCore;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Data;

public class TradingDbContext(DbContextOptions<TradingDbContext> options) : DbContext(options)
{
    public DbSet<WatchlistItem> WatchlistItems => Set<WatchlistItem>();
    public DbSet<TickerDailyClose> TickerDailyCloses => Set<TickerDailyClose>();
    public DbSet<TradingSignal> TradingSignals => Set<TradingSignal>();

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
    }
}
