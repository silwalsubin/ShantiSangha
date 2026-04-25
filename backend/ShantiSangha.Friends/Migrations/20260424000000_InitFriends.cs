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
            // Table names are prefixed with "Friend" to avoid collisions with
            // other modules' tables — the Chat module already owns a public
            // "Messages" table in this database. Using IF NOT EXISTS without a
            // unique prefix would silently skip creation and then fail on the
            // CREATE INDEX step ("column does not exist"), which is exactly
            // how this bit us in production. Always prefix module-owned tables.
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

                CREATE TABLE IF NOT EXISTS ""FriendInvitations"" (
                    ""Id"" uuid NOT NULL,
                    ""InviterUserId"" uuid NOT NULL,
                    ""Token"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""ExpiresAt"" timestamp with time zone NOT NULL,
                    ""AcceptedAt"" timestamp with time zone NULL,
                    ""AcceptedByUserId"" uuid NULL,
                    ""RevokedAt"" timestamp with time zone NULL,
                    CONSTRAINT ""PK_FriendInvitations"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_FriendInvitations_Token"" ON ""FriendInvitations"" (""Token"");
                CREATE INDEX IF NOT EXISTS ""IX_FriendInvitations_InviterUserId_AcceptedAt_RevokedAt""
                    ON ""FriendInvitations"" (""InviterUserId"", ""AcceptedAt"", ""RevokedAt"");

                CREATE TABLE IF NOT EXISTS ""FriendMessages"" (
                    ""Id"" uuid NOT NULL,
                    ""FriendshipId"" uuid NOT NULL,
                    ""SenderUserId"" uuid NOT NULL,
                    ""Kind"" text NOT NULL,
                    ""Body"" text NULL,
                    ""StorageKey"" text NULL,
                    ""DurationMs"" integer NULL,
                    ""SentAt"" timestamp with time zone NOT NULL,
                    ""ReadAt"" timestamp with time zone NULL,
                    CONSTRAINT ""PK_FriendMessages"" PRIMARY KEY (""Id"")
                );
                CREATE INDEX IF NOT EXISTS ""IX_FriendMessages_FriendshipId_SentAt""
                    ON ""FriendMessages"" (""FriendshipId"", ""SentAt"");
                CREATE INDEX IF NOT EXISTS ""IX_FriendMessages_SenderUserId"" ON ""FriendMessages"" (""SenderUserId"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""FriendMessages"";
                DROP TABLE IF EXISTS ""FriendInvitations"";
                DROP TABLE IF EXISTS ""Friendships"";
            ");
        }
    }
}
