using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Practices.Migrations
{
    /// <inheritdoc />
    public partial class DropAiNudgeColumns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Goals"" DROP COLUMN IF EXISTS ""AiNudge"";
                ALTER TABLE ""Goals"" DROP COLUMN IF EXISTS ""AiNudgeAt"";
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Goals"" ADD COLUMN IF NOT EXISTS ""AiNudge"" text;
                ALTER TABLE ""Goals"" ADD COLUMN IF NOT EXISTS ""AiNudgeAt"" timestamp with time zone;
            ");
        }
    }
}
