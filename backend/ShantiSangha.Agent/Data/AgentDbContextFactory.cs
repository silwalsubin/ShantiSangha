using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace ShantiSangha.Agent.Data;

/// <summary>
/// Design-time factory so <c>dotnet ef migrations add ...</c> can construct
/// the context without booting the full Api host (which pulls in Firebase,
/// Redis, S3, etc.). Never used at runtime.
/// </summary>
internal sealed class AgentDbContextFactory : IDesignTimeDbContextFactory<AgentDbContext>
{
    public AgentDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AgentDbContext>()
            .UseNpgsql("Host=localhost;Database=design;Username=x;Password=x")
            .Options;
        return new AgentDbContext(options);
    }
}
