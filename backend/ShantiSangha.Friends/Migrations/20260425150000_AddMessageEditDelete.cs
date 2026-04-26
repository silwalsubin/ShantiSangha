using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    public partial class AddMessageEditDelete : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""FriendMessages""
                    ADD COLUMN IF NOT EXISTS ""EditedAt"" timestamp with time zone NULL,
                    ADD COLUMN IF NOT EXISTS ""DeletedAt"" timestamp with time zone NULL;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""FriendMessages""
                    DROP COLUMN IF EXISTS ""EditedAt"",
                    DROP COLUMN IF EXISTS ""DeletedAt"";
            ");
        }
    }
}
