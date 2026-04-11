using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Wellness.Migrations
{
    /// <inheritdoc />
    public partial class AddDailyMantras : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Only create the new DailyMantras table — other wellness tables
            // (CopingSessions, MoodCheckins, VoiceEntries) already exist in prod
            // from before migrations were added to the repo.
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""DailyMantras"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Content"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_DailyMantras"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_DailyMantras_UserId_Date""
                    ON ""DailyMantras"" (""UserId"", ""Date"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""DailyMantras"";");
        }
    }
}
