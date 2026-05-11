using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddSellSignalAndJournalAndStopOut : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // 1. SellSignalPSell column on UserStrategySettings.
            migrationBuilder.Sql(@"
                ALTER TABLE ""UserStrategySettings""
                ADD COLUMN IF NOT EXISTS ""SellSignalPSell"" numeric(6,4) NOT NULL DEFAULT 0.55;
            ");

            // 2. StopOutLedger — append-only log of stop-out events.
            //    Read by the plan generator to enforce Rule 4 (cooldown).
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""StopOutLedgers"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Ticker"" varchar(16) NOT NULL,
                    ""StoppedAt"" timestamp with time zone NOT NULL,
                    ""ExitPrice"" numeric(18,4) NOT NULL,
                    ""CostBasis"" numeric(18,4) NOT NULL,
                    ""LossPct"" numeric(6,4) NOT NULL,
                    CONSTRAINT ""PK_StopOutLedgers"" PRIMARY KEY (""Id"")
                );
                CREATE INDEX IF NOT EXISTS ""IX_StopOutLedgers_UserId_Ticker_StoppedAt""
                    ON ""StopOutLedgers"" (""UserId"", ""Ticker"", ""StoppedAt"");
            ");

            // 3. TradeJournalEntries — Rule 8 surface.
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""TradeJournalEntries"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Ticker"" varchar(16) NOT NULL,
                    ""Kind"" varchar(16) NOT NULL,
                    ""Price"" numeric(18,4) NULL,
                    ""Shares"" numeric(18,6) NULL,
                    ""Reason"" varchar(500) NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_TradeJournalEntries"" PRIMARY KEY (""Id"")
                );
                CREATE INDEX IF NOT EXISTS ""IX_TradeJournalEntries_UserId_CreatedAt""
                    ON ""TradeJournalEntries"" (""UserId"", ""CreatedAt"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""TradeJournalEntries"";");
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""StopOutLedgers"";");
            migrationBuilder.Sql(@"
                ALTER TABLE ""UserStrategySettings""
                DROP COLUMN IF EXISTS ""SellSignalPSell"";
            ");
        }
    }
}
