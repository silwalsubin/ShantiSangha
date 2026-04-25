using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// <inheritdoc />
    public partial class InitFriends : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""Friendships"" (
                    ""Id"" uuid NOT NULL,
                    ""UserAId"" uuid NOT NULL,
                    ""UserBId"" uuid NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_Friendships"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_Friendships_UserAId_UserBId""
                    ON ""Friendships"" (""UserAId"", ""UserBId"");
                CREATE INDEX IF NOT EXISTS ""IX_Friendships_UserAId"" ON ""Friendships"" (""UserAId"");
                CREATE INDEX IF NOT EXISTS ""IX_Friendships_UserBId"" ON ""Friendships"" (""UserBId"");

                CREATE TABLE IF NOT EXISTS ""Invitations"" (
                    ""Id"" uuid NOT NULL,
                    ""InviterUserId"" uuid NOT NULL,
                    ""Token"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""ExpiresAt"" timestamp with time zone NOT NULL,
                    ""AcceptedAt"" timestamp with time zone NULL,
                    ""AcceptedByUserId"" uuid NULL,
                    ""RevokedAt"" timestamp with time zone NULL,
                    CONSTRAINT ""PK_Invitations"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_Invitations_Token"" ON ""Invitations"" (""Token"");
                CREATE INDEX IF NOT EXISTS ""IX_Invitations_InviterUserId_AcceptedAt_RevokedAt""
                    ON ""Invitations"" (""InviterUserId"", ""AcceptedAt"", ""RevokedAt"");

                CREATE TABLE IF NOT EXISTS ""Messages"" (
                    ""Id"" uuid NOT NULL,
                    ""FriendshipId"" uuid NOT NULL,
                    ""SenderUserId"" uuid NOT NULL,
                    ""Kind"" text NOT NULL,
                    ""Body"" text NULL,
                    ""StorageKey"" text NULL,
                    ""DurationMs"" integer NULL,
                    ""SentAt"" timestamp with time zone NOT NULL,
                    ""ReadAt"" timestamp with time zone NULL,
                    CONSTRAINT ""PK_Messages"" PRIMARY KEY (""Id"")
                );
                CREATE INDEX IF NOT EXISTS ""IX_Messages_FriendshipId_SentAt""
                    ON ""Messages"" (""FriendshipId"", ""SentAt"");
                CREATE INDEX IF NOT EXISTS ""IX_Messages_SenderUserId"" ON ""Messages"" (""SenderUserId"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""Messages"";
                DROP TABLE IF EXISTS ""Invitations"";
                DROP TABLE IF EXISTS ""Friendships"";
            ");
        }
    }
}
