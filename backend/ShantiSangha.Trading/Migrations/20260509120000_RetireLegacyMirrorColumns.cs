using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class RetireLegacyMirrorColumns : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Drop the legacy single-horizon mirror columns. iOS still reads
            // top-level Action / Conviction / TechnicalScore / CompositeScore
            // on the wire DTO, but the API now computes those from the 1M
            // per-horizon columns in the DTO mapper rather than persisting a
            // duplicate copy. The per-horizon columns (Action1W/1M/1Y, ...)
            // remain — they are the source of truth.
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    DROP COLUMN IF EXISTS ""Action"",
                    DROP COLUMN IF EXISTS ""Conviction"",
                    DROP COLUMN IF EXISTS ""TechnicalScore"",
                    DROP COLUMN IF EXISTS ""CompositeScore"";
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Restore the legacy mirror columns. Backfill from the 1M horizon
            // so any code that re-reads the column shape during a rollback
            // sees the same view it had before — the 1M verdict.
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    ADD COLUMN IF NOT EXISTS ""Action""         varchar(8)       NOT NULL DEFAULT 'Hold',
                    ADD COLUMN IF NOT EXISTS ""Conviction""     double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""TechnicalScore"" double precision NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS ""CompositeScore"" double precision NOT NULL DEFAULT 0;
                UPDATE ""TradingSignals""
                    SET ""Action""         = ""Action1M"",
                        ""Conviction""     = ""Conviction1M"",
                        ""TechnicalScore"" = ""Technical1M"",
                        ""CompositeScore"" = ""Composite1M"";
            ");
        }
    }
}
