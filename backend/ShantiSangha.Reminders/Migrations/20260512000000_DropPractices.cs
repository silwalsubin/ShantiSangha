using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Reminders.Migrations
{
    /// Retires the practices feature. The Practices DbContext and module are
    /// gone; this drops the tables that the prior `InitReminders` migration
    /// renamed Goals → Practices into. Lives in the Reminders module because
    /// Reminders is the surviving owner of recurring-task semantics.
    public partial class DropPractices : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""JourneyReflections"";
                DROP TABLE IF EXISTS ""PracticeActivities"";
                DROP TABLE IF EXISTS ""PracticeCheckIns"";
                DROP TABLE IF EXISTS ""Practices"";
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Cannot restore — practices data is gone after Up. If you need
            // to roll back, restore from a backup taken before the deploy.
        }
    }
}
