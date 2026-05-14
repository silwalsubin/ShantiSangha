using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace ShantiSangha.Friends.Data;

/// <summary>
/// Design-time factory so <c>dotnet ef migrations add ...</c> can construct
/// the context without booting the full Api host (which pulls in Firebase,
/// Redis, S3, etc.). Never used at runtime — runtime DI registers the real
/// connection string in <c>DependencyInjection.AddFriendsModule</c>.
/// </summary>
internal sealed class FriendsDbContextFactory : IDesignTimeDbContextFactory<FriendsDbContext>
{
    public FriendsDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<FriendsDbContext>()
            .UseNpgsql("Host=localhost;Database=design;Username=x;Password=x")
            .Options;
        return new FriendsDbContext(options);
    }
}
