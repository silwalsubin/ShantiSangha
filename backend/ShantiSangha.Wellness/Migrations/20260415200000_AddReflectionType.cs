using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Wellness.Migrations
{
    public partial class AddReflectionType : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Type",
                table: "DailyReflections",
                type: "text",
                nullable: false,
                defaultValue: "Regular");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Type",
                table: "DailyReflections");
        }
    }
}
