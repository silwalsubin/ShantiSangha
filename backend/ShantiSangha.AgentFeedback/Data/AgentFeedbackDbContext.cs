using Microsoft.EntityFrameworkCore;
using ShantiSangha.AgentFeedback.Models;

namespace ShantiSangha.AgentFeedback.Data;

public class AgentFeedbackDbContext(DbContextOptions<AgentFeedbackDbContext> options) : DbContext(options)
{
    public DbSet<AgentFeedbackEntry> Entries => Set<AgentFeedbackEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AgentFeedbackEntry>(e =>
        {
            e.ToTable("AgentFeedbackEntries");
            e.HasIndex(x => new { x.UserId, x.CreatedAt });
            e.HasIndex(x => x.Type);
            e.Property(x => x.Type).HasConversion<string>();
            e.Property(x => x.Severity).HasConversion<string>();
        });
    }
}
