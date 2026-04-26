using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Notifications.Migrations
{
    public partial class InitNotifications : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Module-prefixed table name (`AppNotifications`, not just
            // `Notifications`) for the same collision-avoidance reason the
            // Friends module learned: a generic name like `Notifications`
            // is too easy for another producer (push, email, web) to want.
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""AppNotifications"" (
                    ""Id"" uuid NOT NULL,
                    ""RecipientUserId"" uuid NOT NULL,
                    ""Type"" text NOT NULL,
                    ""PayloadJson"" text NOT NULL DEFAULT '{}',
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""ViewedAt"" timestamp with time zone NULL,
                    CONSTRAINT ""PK_AppNotifications"" PRIMARY KEY (""Id"")
                );

                -- Unread-count query (RecipientUserId + ViewedAt IS NULL)
                CREATE INDEX IF NOT EXISTS ""IX_AppNotifications_RecipientUserId_ViewedAt""
                    ON ""AppNotifications"" (""RecipientUserId"", ""ViewedAt"");

                -- Inbox list query (RecipientUserId, newest first)
                CREATE INDEX IF NOT EXISTS ""IX_AppNotifications_RecipientUserId_CreatedAt""
                    ON ""AppNotifications"" (""RecipientUserId"", ""CreatedAt"" DESC);
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""AppNotifications"";");
        }
    }
}
