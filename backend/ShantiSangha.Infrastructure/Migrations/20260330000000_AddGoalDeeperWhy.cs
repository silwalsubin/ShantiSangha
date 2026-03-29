using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddGoalDeeperWhy : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "DeeperWhy",
                table: "Goals",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DeeperWhy",
                table: "Goals");
        }
    }
}
