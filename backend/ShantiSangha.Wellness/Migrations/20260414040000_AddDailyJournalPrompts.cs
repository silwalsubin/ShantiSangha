using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Wellness.Migrations
{
    /// <inheritdoc />
    public partial class AddDailyJournalPrompts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""DailyJournalPrompts"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Content"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_DailyJournalPrompts"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_DailyJournalPrompts_UserId_Date""
                    ON ""DailyJournalPrompts"" (""UserId"", ""Date"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""DailyJournalPrompts"";");
        }
    }
}
