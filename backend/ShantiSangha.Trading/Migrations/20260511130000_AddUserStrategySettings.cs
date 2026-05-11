using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddUserStrategySettings : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""UserStrategySettings"" (
                    ""UserId"" uuid NOT NULL,
                    ""StopLossPct"" numeric(6,4) NOT NULL DEFAULT 0.07,
                    ""TakeProfitPct"" numeric(6,4) NOT NULL DEFAULT 0.10,
                    ""EntryThresholdPBuy"" numeric(6,4) NOT NULL DEFAULT 0.60,
                    ""EntryHorizon"" varchar(4) NOT NULL DEFAULT '1W',
                    ""CooldownDays"" integer NOT NULL DEFAULT 5,
                    ""PositionCapPct"" numeric(6,4) NOT NULL DEFAULT 0.10,
                    ""MinSectors"" integer NOT NULL DEFAULT 8,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_UserStrategySettings"" PRIMARY KEY (""UserId"")
                );
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""UserStrategySettings"";");
        }
    }
}
