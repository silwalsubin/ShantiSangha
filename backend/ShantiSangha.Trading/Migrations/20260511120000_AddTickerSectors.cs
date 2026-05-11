using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddTickerSectors : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""TickerSectors"" (
                    ""Ticker"" varchar(16) NOT NULL,
                    ""Sector"" varchar(64) NOT NULL,
                    ""Name"" varchar(256) NULL,
                    ""FetchedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_TickerSectors"" PRIMARY KEY (""Ticker"")
                );
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""TickerSectors"";");
        }
    }
}
