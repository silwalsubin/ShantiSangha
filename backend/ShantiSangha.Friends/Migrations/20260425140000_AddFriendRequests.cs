using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    public partial class AddFriendRequests : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""FriendRequests"" (
                    ""Id"" uuid NOT NULL,
                    ""FromUserId"" uuid NOT NULL,
                    ""ToUserId"" uuid NOT NULL,
                    ""Status"" text NOT NULL DEFAULT 'Pending',
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""RespondedAt"" timestamp with time zone NULL,
                    CONSTRAINT ""PK_FriendRequests"" PRIMARY KEY (""Id"")
                );

                -- Recipient's inbox query (pending requests for me, newest first)
                CREATE INDEX IF NOT EXISTS ""IX_FriendRequests_ToUserId_Status_CreatedAt""
                    ON ""FriendRequests"" (""ToUserId"", ""Status"", ""CreatedAt"" DESC);

                -- Sender's outgoing list
                CREATE INDEX IF NOT EXISTS ""IX_FriendRequests_FromUserId_Status_CreatedAt""
                    ON ""FriendRequests"" (""FromUserId"", ""Status"", ""CreatedAt"" DESC);
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""FriendRequests"";");
        }
    }
}
