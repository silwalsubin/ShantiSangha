using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.AgentFeedback.Migrations
{
    /// First migration for the agent self-reporting module. Creates a single
    /// table the in-app agent writes to via `report_feedback`. Rows are
    /// dev-only — the read controller is gated to the maintainer's email.
    public partial class InitAgentFeedback : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""AgentFeedbackEntries"" (
                    ""Id"" uuid NOT NULL PRIMARY KEY,
                    ""UserId"" uuid NOT NULL,
                    ""Type"" text NOT NULL,
                    ""Severity"" text NOT NULL,
                    ""Title"" text NOT NULL,
                    ""Context"" text NOT NULL,
                    ""Suggestion"" text NULL,
                    ""TriggeringMessageId"" uuid NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL
                );

                CREATE INDEX IF NOT EXISTS ""IX_AgentFeedbackEntries_UserId_CreatedAt""
                    ON ""AgentFeedbackEntries"" (""UserId"", ""CreatedAt"");
                CREATE INDEX IF NOT EXISTS ""IX_AgentFeedbackEntries_Type""
                    ON ""AgentFeedbackEntries"" (""Type"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""AgentFeedbackEntries"";");
        }
    }
}
