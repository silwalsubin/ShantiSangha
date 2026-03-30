using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddGoalProgress : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "Progress",
                table: "Goals",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Progress",
                table: "Goals");
        }
    }
}
