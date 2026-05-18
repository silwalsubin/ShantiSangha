using Microsoft.EntityFrameworkCore;
using ShantiSangha.Reminders.Models;

namespace ShantiSangha.Reminders.Data;

public class RemindersDbContext(DbContextOptions<RemindersDbContext> options) : DbContext(options)
{
    public DbSet<Reminder> Reminders => Set<Reminder>();
    public DbSet<ReminderCollaborator> ReminderCollaborators => Set<ReminderCollaborator>();

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

        modelBuilder.Entity<ReminderCollaborator>(e =>
        {
            e.ToTable("ReminderCollaborators");
            e.HasKey(rc => new { rc.ReminderId, rc.UserId });
            // Side-of-the-join lookup: "give me every reminder shared with
            // this user." Hot path — runs on every reminder list call.
            e.HasIndex(rc => rc.UserId);
            e.HasOne(rc => rc.Reminder)
                .WithMany(r => r.Collaborators)
                .HasForeignKey(rc => rc.ReminderId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
