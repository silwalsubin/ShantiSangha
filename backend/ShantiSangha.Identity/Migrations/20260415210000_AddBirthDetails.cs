using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Identity.Migrations
{
    public partial class AddBirthDetails : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateOnly>(
                name: "BirthDate",
                table: "Profiles",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BirthTime",
                table: "Profiles",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BirthPlace",
                table: "Profiles",
                type: "text",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "BirthDate", table: "Profiles");
            migrationBuilder.DropColumn(name: "BirthTime", table: "Profiles");
            migrationBuilder.DropColumn(name: "BirthPlace", table: "Profiles");
        }
    }
}
