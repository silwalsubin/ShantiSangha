using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    public partial class AddMessageReactions : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""FriendMessageReactions"" (
                    ""MessageId"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Emoji"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_FriendMessageReactions"" PRIMARY KEY (""MessageId"", ""UserId"")
                );
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""FriendMessageReactions"";");
        }
    }
}
