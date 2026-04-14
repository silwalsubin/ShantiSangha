using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Wellness.Migrations
{
    /// <inheritdoc />
    public partial class DropMoodCheckinsAddDailyReflections : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""MoodCheckins"";");

            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""DailyReflections"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Content"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_DailyReflections"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_DailyReflections_UserId_Date""
                    ON ""DailyReflections"" (""UserId"", ""Date"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""DailyReflections"";");

            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""MoodCheckins"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Score"" integer NOT NULL,
                    ""Notes"" text,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_MoodCheckins"" PRIMARY KEY (""Id"")
                );
                CREATE INDEX IF NOT EXISTS ""IX_MoodCheckins_UserId_CreatedAt""
                    ON ""MoodCheckins"" (""UserId"", ""CreatedAt"");
            ");
        }
    }
}
