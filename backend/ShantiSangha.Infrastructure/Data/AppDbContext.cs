using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;

namespace ShantiSangha.Infrastructure.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<Conversation> Conversations => Set<Conversation>();
    public DbSet<Message> Messages => Set<Message>();
    public DbSet<Journal> Journals => Set<Journal>();
    public DbSet<MoodCheckin> MoodCheckins => Set<MoodCheckin>();
    public DbSet<CopingSession> CopingSessions => Set<CopingSession>();
    public DbSet<SavedInsight> SavedInsights => Set<SavedInsight>();
    public DbSet<Summary> Summaries => Set<Summary>();
    public DbSet<VoiceEntry> VoiceEntries => Set<VoiceEntry>();
    public DbSet<SafetyEvent> SafetyEvents => Set<SafetyEvent>();
    public DbSet<Goal> Goals => Set<Goal>();
    public DbSet<GoalCheckIn> GoalCheckIns => Set<GoalCheckIn>();
    public DbSet<GoalActivity> GoalActivities => Set<GoalActivity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("vector");

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

        modelBuilder.Entity<Message>(e =>
        {
            e.Property(m => m.Role).HasConversion<string>();
            e.HasIndex(m => m.ConversationId);
        });

        modelBuilder.Entity<MoodCheckin>(e =>
        {
            e.HasIndex(m => new { m.UserId, m.CreatedAt });
        });

        modelBuilder.Entity<Summary>(e =>
        {
            e.Property(s => s.SourceType).HasConversion<string>();
        });

        modelBuilder.Entity<VoiceEntry>(e =>
        {
            e.Property(v => v.Status).HasConversion<string>();
        });

        modelBuilder.Entity<SafetyEvent>(e =>
        {
            e.Property(s => s.EventType).HasConversion<string>();
            e.HasIndex(s => new { s.UserId, s.CreatedAt });
        });

        modelBuilder.Entity<Goal>(e =>
        {
            e.HasIndex(g => g.UserId);
            e.HasIndex(g => new { g.UserId, g.Title }).IsUnique();
            e.Property(g => g.Type).HasConversion<string>();
            e.Property(g => g.Frequency).HasConversion<string>();
        });

        modelBuilder.Entity<GoalCheckIn>(e =>
        {
            e.HasIndex(c => c.GoalId);
            e.HasIndex(c => new { c.GoalId, c.Date }).IsUnique();
        });

        modelBuilder.Entity<GoalActivity>(e =>
        {
            e.HasIndex(a => new { a.GoalId, a.CreatedAt });
        });
    }
}
