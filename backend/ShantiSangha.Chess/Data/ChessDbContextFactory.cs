using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace ShantiSangha.Chess.Data;

/// Design-time factory so `dotnet ef migrations add ...` can construct the
/// context without booting the full Api host. The dummy connection string is
/// only used at design time; runtime DI supplies the real one in
/// `DependencyInjection.AddChessModule`.
internal sealed class ChessDbContextFactory : IDesignTimeDbContextFactory<ChessDbContext>
{
    public ChessDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<ChessDbContext>()
            .UseNpgsql("Host=localhost;Database=design;Username=x;Password=x")
            .Options;
        return new ChessDbContext(options);
    }
}
