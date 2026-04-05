using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddGoalAiNudge : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "AiNudge",
                table: "Goals",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "AiNudgeAt",
                table: "Goals",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "AiNudge", table: "Goals");
            migrationBuilder.DropColumn(name: "AiNudgeAt", table: "Goals");
        }
    }
}
