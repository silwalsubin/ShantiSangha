using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Identity.Migrations
{
    public partial class AddFriendMessageNotificationPreference : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Profiles""
                    ADD COLUMN IF NOT EXISTS ""NotifyOnFriendMessages"" boolean NOT NULL DEFAULT TRUE;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Profiles""
                    DROP COLUMN IF EXISTS ""NotifyOnFriendMessages"";
            ");
        }
    }
}
