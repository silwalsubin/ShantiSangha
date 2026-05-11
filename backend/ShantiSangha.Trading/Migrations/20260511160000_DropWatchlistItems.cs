using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    /// <summary>
    /// Removes the WatchlistItems table. The feature was retired
    /// end-to-end (UI, services, endpoints) so the table no longer
    /// serves any purpose. Down migration recreates the original shape
    /// from InitTrading so a rollback restores the schema.
    /// </summary>
    public partial class DropWatchlistItems : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""WatchlistItems"";");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""WatchlistItems"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Ticker"" varchar(16) NOT NULL,
                    ""AddedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_WatchlistItems"" PRIMARY KEY (""Id"")
                );
                CREATE INDEX IF NOT EXISTS ""IX_WatchlistItems_UserId""
                    ON ""WatchlistItems"" (""UserId"");
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_WatchlistItems_UserId_Ticker""
                    ON ""WatchlistItems"" (""UserId"", ""Ticker"");
            ");
        }
    }
}
