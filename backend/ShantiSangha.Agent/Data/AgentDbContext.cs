using Microsoft.EntityFrameworkCore;
using ShantiSangha.Agent.Models;

namespace ShantiSangha.Agent.Data;

public class AgentDbContext(DbContextOptions<AgentDbContext> options) : DbContext(options)
{
    public DbSet<AgentMessage> AgentMessages => Set<AgentMessage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AgentMessage>(e =>
        {
            e.ToTable("AgentMessages");
            e.HasIndex(m => new { m.UserId, m.CreatedAt });
            e.Property(m => m.Role).HasConversion<string>();
        });
    }
}
