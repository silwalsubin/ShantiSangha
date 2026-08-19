using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Npgsql;

namespace ShantiSangha.Memory.Data;

/// Design-time factory so `dotnet ef migrations add` works without booting the
/// full Api host (which fail-fast loads env vars). Never used at runtime.
internal sealed class MemoryDbContextFactory : IDesignTimeDbContextFactory<MemoryDbContext>
{
    public MemoryDbContext CreateDbContext(string[] args)
    {
        var dataSourceBuilder = new NpgsqlDataSourceBuilder("Host=localhost;Database=design");
        dataSourceBuilder.UseVector();

        var options = new DbContextOptionsBuilder<MemoryDbContext>()
            .UseNpgsql(dataSourceBuilder.Build(), o => o.UseVector())
            .Options;

        return new MemoryDbContext(options);
    }
}
