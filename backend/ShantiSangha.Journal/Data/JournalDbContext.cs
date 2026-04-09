using Microsoft.EntityFrameworkCore;
using ShantiSangha.Journal.Models;

namespace ShantiSangha.Journal.Data;

public class JournalDbContext(DbContextOptions<JournalDbContext> options) : DbContext(options)
{
    public DbSet<Models.Journal> Journals => Set<Models.Journal>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("vector");

        modelBuilder.Entity<Models.Journal>(e =>
        {
            e.HasIndex(j => j.UserId);
        });
    }
}
