using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Identity.Migrations
{
    public partial class AddProfileLocationDetails : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Country",
                table: "Profiles",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "State",
                table: "Profiles",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "City",
                table: "Profiles",
                type: "text",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "Country", table: "Profiles");
            migrationBuilder.DropColumn(name: "State", table: "Profiles");
            migrationBuilder.DropColumn(name: "City", table: "Profiles");
        }
    }
}
