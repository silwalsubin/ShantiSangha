using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Practices.Migrations
{
    /// <inheritdoc />
    public partial class AddJourneyReflections : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""JourneyReflections"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""FromDate"" date NOT NULL,
                    ""ToDate"" date NOT NULL,
                    ""Content"" text NOT NULL,
                    ""InputHash"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_JourneyReflections"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_JourneyReflections_UserId_FromDate_ToDate""
                    ON ""JourneyReflections"" (""UserId"", ""FromDate"", ""ToDate"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""JourneyReflections"";");
        }
    }
}
