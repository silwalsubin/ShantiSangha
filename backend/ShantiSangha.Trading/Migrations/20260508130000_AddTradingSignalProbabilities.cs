using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddTradingSignalProbabilities : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Per-horizon probabilistic verdict columns sourced from the
            // upcoming GBM classifier: (pBuy, pHold, pSell) + expectedReturn
            // for each of 1W / 1M / 1Y. PHold defaults to 1 (fully "Hold")
            // so legacy rows and rows from a pre-GBM Lambda revision read
            // as a confident hold instead of an all-zero ambiguous verdict.
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    ADD COLUMN IF NOT EXISTS ""PBuy1W""           double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""PHold1W""          double precision NOT NULL DEFAULT 1,
                    ADD COLUMN IF NOT EXISTS ""PSell1W""          double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""ExpectedReturn1W"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""PBuy1M""           double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""PHold1M""          double precision NOT NULL DEFAULT 1,
                    ADD COLUMN IF NOT EXISTS ""PSell1M""          double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""ExpectedReturn1M"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""PBuy1Y""           double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""PHold1Y""          double precision NOT NULL DEFAULT 1,
                    ADD COLUMN IF NOT EXISTS ""PSell1Y""          double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""ExpectedReturn1Y"" double precision NOT NULL DEFAULT 0;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    DROP COLUMN IF EXISTS ""PBuy1W"",
                    DROP COLUMN IF EXISTS ""PHold1W"",
                    DROP COLUMN IF EXISTS ""PSell1W"",
                    DROP COLUMN IF EXISTS ""ExpectedReturn1W"",
                    DROP COLUMN IF EXISTS ""PBuy1M"",
                    DROP COLUMN IF EXISTS ""PHold1M"",
                    DROP COLUMN IF EXISTS ""PSell1M"",
                    DROP COLUMN IF EXISTS ""ExpectedReturn1M"",
                    DROP COLUMN IF EXISTS ""PBuy1Y"",
                    DROP COLUMN IF EXISTS ""PHold1Y"",
                    DROP COLUMN IF EXISTS ""PSell1Y"",
                    DROP COLUMN IF EXISTS ""ExpectedReturn1Y"";
            ");
        }
    }
}
