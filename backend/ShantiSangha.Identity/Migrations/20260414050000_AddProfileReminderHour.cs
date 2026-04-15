using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Identity.Migrations
{
    /// <inheritdoc />
    public partial class AddProfileReminderHour : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Profiles"" ADD COLUMN IF NOT EXISTS ""ReminderHour"" integer;
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Profiles"" DROP COLUMN IF EXISTS ""ReminderHour"";
            ");
        }
    }
}
