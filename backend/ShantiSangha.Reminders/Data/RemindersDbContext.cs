using Microsoft.EntityFrameworkCore;
using ShantiSangha.Reminders.Models;

namespace ShantiSangha.Reminders.Data;

public class RemindersDbContext(DbContextOptions<RemindersDbContext> options) : DbContext(options)
{
    public DbSet<Reminder> Reminders => Set<Reminder>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Reminder>(e =>
        {
            e.ToTable("Reminders");
            e.HasIndex(r => r.UserId);
            e.HasIndex(r => new { r.UserId, r.Date });
            e.HasIndex(r => r.ConnectionId);
            e.Property(r => r.Recurrence).HasConversion<string>();
        });
    }
}
