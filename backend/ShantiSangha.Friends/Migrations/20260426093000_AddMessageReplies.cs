using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    public partial class AddMessageReplies : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""FriendMessages""
                    ADD COLUMN IF NOT EXISTS ""ReplyToMessageId"" uuid NULL;

                CREATE INDEX IF NOT EXISTS ""IX_FriendMessages_ReplyToMessageId""
                    ON ""FriendMessages"" (""ReplyToMessageId"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP INDEX IF EXISTS ""IX_FriendMessages_ReplyToMessageId"";

                ALTER TABLE ""FriendMessages""
                    DROP COLUMN IF EXISTS ""ReplyToMessageId"";
            ");
        }
    }
}
