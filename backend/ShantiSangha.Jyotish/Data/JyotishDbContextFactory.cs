using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Npgsql;

namespace ShantiSangha.Jyotish.Data;

/// <summary>
/// Design-time factory so `dotnet ef migrations add` can build a DbContext
/// without bootstrapping the full API host. Not used at runtime.
/// </summary>
public class JyotishDbContextFactory : IDesignTimeDbContextFactory<JyotishDbContext>
{
    public JyotishDbContext CreateDbContext(string[] args)
    {
        var connStr = Environment.GetEnvironmentVariable("DATABASE_URL")
            ?? "Host=localhost;Port=5432;Database=shantisangha;Username=postgres;Password=postgres";
        var dataSourceBuilder = new NpgsqlDataSourceBuilder(connStr);
        dataSourceBuilder.UseVector();
        var dataSource = dataSourceBuilder.Build();

        var options = new DbContextOptionsBuilder<JyotishDbContext>()
            .UseNpgsql(dataSource, o => o.UseVector())
            .Options;

        return new JyotishDbContext(options);
    }
}
