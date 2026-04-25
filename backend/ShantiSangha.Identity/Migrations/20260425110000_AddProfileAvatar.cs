using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Identity.Migrations
{
    public partial class AddProfileAvatar : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AvatarKey",
                table: "Profiles",
                type: "text",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "AvatarKey", table: "Profiles");
        }
    }
}
