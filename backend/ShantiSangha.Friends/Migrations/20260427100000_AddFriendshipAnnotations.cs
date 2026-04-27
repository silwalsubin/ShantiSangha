using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    public partial class AddFriendshipAnnotations : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""FriendshipAnnotations"" (
                    ""FriendshipId"" uuid NOT NULL,
                    ""OwnerUserId"" uuid NOT NULL,
                    ""Nickname"" text NULL,
                    ""PrivateNotes"" text NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_FriendshipAnnotations"" PRIMARY KEY (""FriendshipId"", ""OwnerUserId""),
                    CONSTRAINT ""FK_FriendshipAnnotations_Friendships"" FOREIGN KEY (""FriendshipId"")
                        REFERENCES ""Friendships"" (""Id"") ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS ""IX_FriendshipAnnotations_OwnerUserId""
                    ON ""FriendshipAnnotations"" (""OwnerUserId"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""FriendshipAnnotations"";");
        }
    }
}
