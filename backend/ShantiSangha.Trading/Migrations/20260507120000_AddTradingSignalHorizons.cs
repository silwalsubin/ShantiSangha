using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddTradingSignalHorizons : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Add per-horizon verdict columns to TradingSignals.
            // All NOT NULL with DEFAULT so existing rows backfill cleanly —
            // signals are recomputed daily, so old rows shadowing the 1M
            // verdict at zero is fine; tomorrow's batch fills them in.
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    ADD COLUMN IF NOT EXISTS ""Action1W""    varchar(8)       NOT NULL DEFAULT 'Hold',
                    ADD COLUMN IF NOT EXISTS ""Action1M""    varchar(8)       NOT NULL DEFAULT 'Hold',
                    ADD COLUMN IF NOT EXISTS ""Action1Y""    varchar(8)       NOT NULL DEFAULT 'Hold',
                    ADD COLUMN IF NOT EXISTS ""Conviction1W"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Conviction1M"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Conviction1Y"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Technical1W"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Technical1M"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Technical1Y"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Composite1W"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Composite1M"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""Composite1Y"" double precision NOT NULL DEFAULT 0;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    DROP COLUMN IF EXISTS ""Action1W"",
                    DROP COLUMN IF EXISTS ""Action1M"",
                    DROP COLUMN IF EXISTS ""Action1Y"",
                    DROP COLUMN IF EXISTS ""Conviction1W"",
                    DROP COLUMN IF EXISTS ""Conviction1M"",
                    DROP COLUMN IF EXISTS ""Conviction1Y"",
                    DROP COLUMN IF EXISTS ""Technical1W"",
                    DROP COLUMN IF EXISTS ""Technical1M"",
                    DROP COLUMN IF EXISTS ""Technical1Y"",
                    DROP COLUMN IF EXISTS ""Composite1W"",
                    DROP COLUMN IF EXISTS ""Composite1M"",
                    DROP COLUMN IF EXISTS ""Composite1Y"";
            ");
        }
    }
}
