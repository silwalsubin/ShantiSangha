using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Wellness.Migrations
{
    /// <inheritdoc />
    public partial class AddDailyReadings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""DailyReadings"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Content"" text NOT NULL,
                    ""Framing"" text NOT NULL DEFAULT 'regular',
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_DailyReadings"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_DailyReadings_UserId_Date""
                    ON ""DailyReadings"" (""UserId"", ""Date"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""DailyReadings"";");
        }
    }
}
