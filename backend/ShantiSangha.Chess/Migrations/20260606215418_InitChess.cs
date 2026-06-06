using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Chess.Migrations
{
    /// <inheritdoc />
    public partial class InitChess : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ChessGames",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FriendshipId = table.Column<Guid>(type: "uuid", nullable: false),
                    WhiteUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BlackUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Fen = table.Column<string>(type: "text", nullable: false),
                    LastMoveUci = table.Column<string>(type: "text", nullable: true),
                    MoveCount = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<string>(type: "text", nullable: false),
                    WinnerUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ChessGames", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ChessGames_BlackUserId",
                table: "ChessGames",
                column: "BlackUserId");

            migrationBuilder.CreateIndex(
                name: "IX_ChessGames_FriendshipId",
                table: "ChessGames",
                column: "FriendshipId");

            migrationBuilder.CreateIndex(
                name: "IX_ChessGames_WhiteUserId",
                table: "ChessGames",
                column: "WhiteUserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ChessGames");
        }
    }
}
