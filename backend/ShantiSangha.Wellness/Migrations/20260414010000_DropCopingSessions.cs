using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Wellness.Migrations
{
    /// <inheritdoc />
    public partial class DropCopingSessions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""CopingSessions"";");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""CopingSessions"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""ExerciseSlug"" text NOT NULL,
                    ""DurationSeconds"" integer NOT NULL,
                    ""Notes"" text,
                    ""CompletedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_CopingSessions"" PRIMARY KEY (""Id"")
                );
            ");
        }
    }
}
