using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Reminders.Migrations
{
    /// First cross-user sharing feature in the app. Owners can grant
    /// accepted friends full peer access (view, edit, complete, delete)
    /// to a single reminder. Cascade on Reminders.Id keeps the join
    /// table tidy when the owner deletes the row.
    public partial class AddReminderCollaborators : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""ReminderCollaborators"" (
                    ""ReminderId"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""AddedByUserId"" uuid NOT NULL,
                    ""AddedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_ReminderCollaborators""
                        PRIMARY KEY (""ReminderId"", ""UserId""),
                    CONSTRAINT ""FK_ReminderCollaborators_Reminders""
                        FOREIGN KEY (""ReminderId"")
                        REFERENCES ""Reminders"" (""Id"")
                        ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS ""IX_ReminderCollaborators_UserId""
                    ON ""ReminderCollaborators"" (""UserId"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""ReminderCollaborators"";
            ");
        }
    }
}
