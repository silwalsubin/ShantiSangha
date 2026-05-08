using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddTradingSignalLastBarDate : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // LastBarDate = the date of the most recent EOD bar that fed
            // the score. Defaults to CURRENT_DATE on add, then immediately
            // backfilled to the row's existing Date column so old rows
            // surface a sensible "as of" value until tomorrow's batch
            // overwrites them with the true last-bar date.
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    ADD COLUMN IF NOT EXISTS ""LastBarDate"" date NOT NULL DEFAULT CURRENT_DATE;
                UPDATE ""TradingSignals"" SET ""LastBarDate"" = ""Date"";
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""TradingSignals""
                    DROP COLUMN IF EXISTS ""LastBarDate"";
            ");
        }
    }
}
