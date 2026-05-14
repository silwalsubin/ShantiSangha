using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Wellness.Migrations
{
    /// <inheritdoc />
    public partial class DropDailyReflectionsAndPortraits : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""DailyReflections"";");
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""Portraits"";");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""DailyReflections"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Content"" text NOT NULL,
                    ""Type"" text NOT NULL DEFAULT 'Regular',
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_DailyReflections"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_DailyReflections_UserId_Date""
                    ON ""DailyReflections"" (""UserId"", ""Date"");
            ");

            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""Portraits"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Content"" text NOT NULL,
                    ""ContextHash"" text NOT NULL DEFAULT '',
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_Portraits"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_Portraits_UserId""
                    ON ""Portraits"" (""UserId"");
            ");
        }
    }
}
