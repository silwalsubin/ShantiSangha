using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// Adds `Recurrence` to `ConnectionDates` so the iOS edit sheet can
    /// distinguish dates that repeat every year (birthday, anniversary,
    /// day-we-met) from one-time anchors (moved cities, started a job).
    /// Existing rows backfill to `Yearly` since that matches what the
    /// previous UI implicitly meant when it offered birthday/anniversary
    /// presets only.
    public partial class AddConnectionDateRecurrence : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""ConnectionDates""
                    ADD COLUMN IF NOT EXISTS ""Recurrence"" text NOT NULL DEFAULT 'Yearly';
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""ConnectionDates"" DROP COLUMN IF EXISTS ""Recurrence"";
            ");
        }
    }
}
