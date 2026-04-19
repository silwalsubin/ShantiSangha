using Microsoft.EntityFrameworkCore;
using ShantiSangha.Jyotish.Models;

namespace ShantiSangha.Jyotish.Data;

public class JyotishDbContext(DbContextOptions<JyotishDbContext> options) : DbContext(options)
{
    public DbSet<JyotishPassageEntity> Passages => Set<JyotishPassageEntity>();
    public DbSet<ChartReadingEntity> Readings => Set<ChartReadingEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("vector");

        modelBuilder.Entity<ChartReadingEntity>(e =>
        {
            e.ToTable("jyotish_readings");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.UserId).IsUnique();  // one reading per user
            e.Property(x => x.ChartHash).IsRequired().HasMaxLength(64);
            e.Property(x => x.SectionsJson).HasColumnType("jsonb").IsRequired();
            e.Property(x => x.PassageUsageJson).HasColumnType("jsonb").IsRequired();
        });

        modelBuilder.Entity<JyotishPassageEntity>(e =>
        {
            e.ToTable("jyotish_passages");
            e.HasKey(x => x.Id);

            e.Property(x => x.PassageId).IsRequired().HasMaxLength(128);
            e.HasIndex(x => x.PassageId).IsUnique();

            e.Property(x => x.SignatureType).IsRequired().HasMaxLength(64);
            e.HasIndex(x => x.SignatureType);

            // Signatures and Themes as Postgres text[] for GIN-indexable membership queries.
            e.Property(x => x.Signatures).HasColumnType("text[]");
            e.Property(x => x.Themes).HasColumnType("text[]");
            e.HasIndex(x => x.Signatures).HasMethod("gin");
            e.HasIndex(x => x.Themes).HasMethod("gin");

            e.Property(x => x.Polarity).HasMaxLength(32);
            e.Property(x => x.Scope).HasMaxLength(32);

            e.Property(x => x.SourceBook).IsRequired().HasMaxLength(256);
            e.Property(x => x.SourceAuthor).IsRequired().HasMaxLength(256);
            e.Property(x => x.SourceLicense).IsRequired().HasMaxLength(64);
            e.Property(x => x.SourceChapter).HasMaxLength(128);
            e.Property(x => x.SourceVerse).HasMaxLength(64);

            // 1536-dim vector matches text-embedding-3-small output.
            e.Property(x => x.Embedding).HasColumnType("vector(1536)");
        });
    }
}
