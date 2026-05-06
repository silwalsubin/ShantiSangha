using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class InitTrading : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
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

                CREATE TABLE IF NOT EXISTS ""StockNatalCharts"" (
                    ""Ticker"" varchar(16) NOT NULL,
                    ""IpoDate"" date NOT NULL,
                    ""IpoTimeEt"" varchar(8) NULL,
                    ""IpoLatitude"" double precision NOT NULL,
                    ""IpoLongitude"" double precision NOT NULL,
                    ""Exchange"" varchar(16) NOT NULL DEFAULT '',
                    ""SignaturesJson"" jsonb NOT NULL DEFAULT '[]'::jsonb,
                    ""ComputedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_StockNatalCharts"" PRIMARY KEY (""Ticker"")
                );

                CREATE TABLE IF NOT EXISTS ""TickerDailyCloses"" (
                    ""Ticker"" varchar(16) NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Open"" numeric(18,4) NOT NULL,
                    ""High"" numeric(18,4) NOT NULL,
                    ""Low"" numeric(18,4) NOT NULL,
                    ""Close"" numeric(18,4) NOT NULL,
                    ""Volume"" bigint NOT NULL,
                    CONSTRAINT ""PK_TickerDailyCloses"" PRIMARY KEY (""Ticker"", ""Date"")
                );

                CREATE TABLE IF NOT EXISTS ""TradingSignals"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Ticker"" varchar(16) NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Action"" varchar(8) NOT NULL,
                    ""Conviction"" double precision NOT NULL,
                    ""TechnicalScore"" double precision NOT NULL,
                    ""AstroScore"" double precision NOT NULL,
                    ""CompositeScore"" double precision NOT NULL,
                    ""ReasoningJson"" jsonb NOT NULL DEFAULT '{}'::jsonb,
                    ""PriceAtSignal"" numeric(18,4) NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_TradingSignals"" PRIMARY KEY (""Id"")
                );

                CREATE INDEX IF NOT EXISTS ""IX_TradingSignals_UserId_Date""
                    ON ""TradingSignals"" (""UserId"", ""Date"");

                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_TradingSignals_UserId_Ticker_Date""
                    ON ""TradingSignals"" (""UserId"", ""Ticker"", ""Date"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""TradingSignals"";
                DROP TABLE IF EXISTS ""TickerDailyCloses"";
                DROP TABLE IF EXISTS ""StockNatalCharts"";
                DROP TABLE IF EXISTS ""WatchlistItems"";
            ");
        }
    }
}
