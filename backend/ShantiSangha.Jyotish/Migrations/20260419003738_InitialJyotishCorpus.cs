using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Pgvector;

#nullable disable

namespace ShantiSangha.Jyotish.Migrations
{
    /// <inheritdoc />
    public partial class InitialJyotishCorpus : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterDatabase()
                .Annotation("Npgsql:PostgresExtension:vector", ",,");

            migrationBuilder.CreateTable(
                name: "jyotish_passages",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    PassageId = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    SignatureType = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Signatures = table.Column<List<string>>(type: "text[]", nullable: false),
                    Title = table.Column<string>(type: "text", nullable: false),
                    Content = table.Column<string>(type: "text", nullable: false),
                    Themes = table.Column<List<string>>(type: "text[]", nullable: false),
                    Polarity = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    Scope = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    SourceBook = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    SourceAuthor = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    SourceYear = table.Column<int>(type: "integer", nullable: false),
                    SourceLicense = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    SourceChapter = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    SourceVerse = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    RawSourceExcerpt = table.Column<string>(type: "text", nullable: false),
                    Source = table.Column<string>(type: "text", nullable: false),
                    Embedding = table.Column<Vector>(type: "vector(1536)", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_jyotish_passages", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_jyotish_passages_PassageId",
                table: "jyotish_passages",
                column: "PassageId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_jyotish_passages_Signatures",
                table: "jyotish_passages",
                column: "Signatures")
                .Annotation("Npgsql:IndexMethod", "gin");

            migrationBuilder.CreateIndex(
                name: "IX_jyotish_passages_SignatureType",
                table: "jyotish_passages",
                column: "SignatureType");

            migrationBuilder.CreateIndex(
                name: "IX_jyotish_passages_Themes",
                table: "jyotish_passages",
                column: "Themes")
                .Annotation("Npgsql:IndexMethod", "gin");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "jyotish_passages");
        }
    }
}
