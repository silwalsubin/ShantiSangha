using Microsoft.EntityFrameworkCore;
using ShantiSangha.Identity.Models;

namespace ShantiSangha.Identity.Data;

public class IdentityDbContext(DbContextOptions<IdentityDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<SafetyEvent> SafetyEvents => Set<SafetyEvent>();
    public DbSet<DeviceToken> DeviceTokens => Set<DeviceToken>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(e =>
        {
            e.HasIndex(u => u.ClerkId).IsUnique();
            e.HasIndex(u => u.Email).IsUnique();
        });

        modelBuilder.Entity<Profile>(e =>
        {
            e.HasOne(p => p.User).WithOne(u => u.Profile)
                .HasForeignKey<Profile>(p => p.UserId);
        });

        modelBuilder.Entity<SafetyEvent>(e =>
        {
            e.Property(s => s.EventType).HasConversion<string>();
            e.HasIndex(s => new { s.UserId, s.CreatedAt });
        });

        modelBuilder.Entity<DeviceToken>(e =>
        {
            e.HasIndex(d => d.Token).IsUnique();
            e.HasIndex(d => d.UserId);
            e.HasOne<User>().WithMany().HasForeignKey(d => d.UserId);
        });
    }
}
