using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Jyotish.Migrations
{
    /// <inheritdoc />
    public partial class AddChartReadings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "jyotish_readings",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ChartHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    SectionsJson = table.Column<string>(type: "jsonb", nullable: false),
                    PassageUsageJson = table.Column<string>(type: "jsonb", nullable: false),
                    GeneratedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_jyotish_readings", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_jyotish_readings_UserId",
                table: "jyotish_readings",
                column: "UserId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "jyotish_readings");
        }
    }
}
