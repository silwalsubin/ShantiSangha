using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Jyotish.Migrations
{
    /// <inheritdoc />
    public partial class AddPairReadings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "jyotish_pair_readings",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ViewerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    SubjectUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ChartHashPair = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    SectionsJson = table.Column<string>(type: "jsonb", nullable: false),
                    PassageUsageJson = table.Column<string>(type: "jsonb", nullable: false),
                    GeneratedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_jyotish_pair_readings", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_jyotish_pair_readings_ViewerUserId_SubjectUserId",
                table: "jyotish_pair_readings",
                columns: new[] { "ViewerUserId", "SubjectUserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_jyotish_pair_readings_SubjectUserId",
                table: "jyotish_pair_readings",
                column: "SubjectUserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "jyotish_pair_readings");
        }
    }
}
