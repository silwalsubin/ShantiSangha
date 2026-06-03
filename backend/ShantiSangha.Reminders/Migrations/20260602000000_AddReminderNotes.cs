using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Reminders.Migrations
{
    /// Free-text notes on a reminder — the user's own jottings plus
    /// anything the reminder-scoped assistant writes when planning it.
    public partial class AddReminderNotes : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Reminders""
                ADD COLUMN IF NOT EXISTS ""Notes"" text NULL;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Reminders""
                DROP COLUMN IF EXISTS ""Notes"";
            ");
        }
    }
}
