using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Reminders.Migrations
{
    /// Unification of `Goals` (date-based one-time) + `ConnectionDates`
    /// (circle-profile dates) into a single `Reminders` table, and rename
    /// of the remaining recurring-only `Goals` table to `Practices`.
    ///
    /// Lives in the Reminders module because it owns the new schema and
    /// the data move flows TO it. The Practices DbContext does not yet
    /// have a follow-up migration of its own — its model already matches
    /// the post-rename shape.
    public partial class InitReminders : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // ── 1. Create the new Reminders table ─────────────────────
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""Reminders"" (
                    ""Id"" uuid NOT NULL PRIMARY KEY,
                    ""UserId"" uuid NOT NULL,
                    ""Label"" text NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Recurrence"" text NOT NULL DEFAULT 'None',
                    ""RemindersEnabled"" boolean NOT NULL DEFAULT TRUE,
                    ""ConnectionId"" uuid NULL,
                    ""CompletedAt"" timestamp with time zone NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL
                );

                CREATE INDEX IF NOT EXISTS ""IX_Reminders_UserId""
                    ON ""Reminders"" (""UserId"");
                CREATE INDEX IF NOT EXISTS ""IX_Reminders_UserId_Date""
                    ON ""Reminders"" (""UserId"", ""Date"");
                CREATE INDEX IF NOT EXISTS ""IX_Reminders_ConnectionId""
                    ON ""Reminders"" (""ConnectionId"");
            ");

            // ── 2. Copy OneTime goals → Reminders ─────────────────────
            // Preserve Ids so any stale client-side references resolve.
            migrationBuilder.Sql(@"
                INSERT INTO ""Reminders"" (
                    ""Id"", ""UserId"", ""Label"", ""Date"",
                    ""Recurrence"", ""RemindersEnabled"", ""ConnectionId"",
                    ""CompletedAt"", ""CreatedAt"")
                SELECT
                    ""Id"", ""UserId"", ""Title"", ""TargetDate"",
                    'None', TRUE, NULL,
                    ""CompletedAt"", ""CreatedAt""
                FROM ""Goals""
                WHERE ""Type"" = 'OneTime' AND ""TargetDate"" IS NOT NULL;
            ");

            // ── 3. Copy circle-profile dates → Reminders ──────────────
            // Owner's UserId comes from the Connection; ConnectionId
            // kept so a profile screen can still list its dates.
            // 'Once' collapses to 'None'; 'Yearly' stays.
            migrationBuilder.Sql(@"
                INSERT INTO ""Reminders"" (
                    ""Id"", ""UserId"", ""Label"", ""Date"",
                    ""Recurrence"", ""RemindersEnabled"", ""ConnectionId"",
                    ""CompletedAt"", ""CreatedAt"")
                SELECT
                    cd.""Id"", c.""OwnerUserId"", cd.""Label"", cd.""Date"",
                    CASE WHEN cd.""Recurrence"" = 'Yearly' THEN 'Yearly' ELSE 'None' END,
                    TRUE, cd.""ConnectionId"",
                    NULL, cd.""CreatedAt""
                FROM ""ConnectionDates"" cd
                JOIN ""Connections"" c ON c.""Id"" = cd.""ConnectionId"";
            ");

            // ── 4. Drop the migrated OneTime goal data ────────────────
            migrationBuilder.Sql(@"
                DELETE FROM ""GoalCheckIns""
                    WHERE ""GoalId"" IN (SELECT ""Id"" FROM ""Goals"" WHERE ""Type"" = 'OneTime');
                DELETE FROM ""GoalActivities""
                    WHERE ""GoalId"" IN (SELECT ""Id"" FROM ""Goals"" WHERE ""Type"" = 'OneTime');
                DELETE FROM ""Goals"" WHERE ""Type"" = 'OneTime';
            ");

            // ── 5. ConnectionDates fully superseded ───────────────────
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""ConnectionDates"";
            ");

            // ── 6. Rename Goals → Practices + drop OneTime-only cols ──
            // Recurring practices live on alone here. The OneTime
            // discriminator and its supporting columns are now dead.
            migrationBuilder.Sql(@"
                ALTER TABLE ""Goals"" RENAME TO ""Practices"";
                ALTER TABLE ""GoalCheckIns"" RENAME TO ""PracticeCheckIns"";
                ALTER TABLE ""GoalActivities"" RENAME TO ""PracticeActivities"";

                ALTER TABLE ""PracticeCheckIns"" RENAME COLUMN ""GoalId"" TO ""PracticeId"";
                ALTER TABLE ""PracticeActivities"" RENAME COLUMN ""GoalId"" TO ""PracticeId"";

                ALTER TABLE ""Practices"" DROP COLUMN IF EXISTS ""Type"";
                ALTER TABLE ""Practices"" DROP COLUMN IF EXISTS ""TargetDate"";
                ALTER TABLE ""Practices"" DROP COLUMN IF EXISTS ""Progress"";
                ALTER TABLE ""Practices"" DROP COLUMN IF EXISTS ""CompletedAt"";
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Down is best-effort. Migrated OneTime goal data cannot be
            // rebuilt — only the schema reshapes. If you ever need true
            // rollback, restore from a backup taken before the Up.
            migrationBuilder.Sql(@"
                ALTER TABLE ""Practices"" ADD COLUMN IF NOT EXISTS ""Type"" text NOT NULL DEFAULT 'Recurring';
                ALTER TABLE ""Practices"" ADD COLUMN IF NOT EXISTS ""TargetDate"" date NULL;
                ALTER TABLE ""Practices"" ADD COLUMN IF NOT EXISTS ""Progress"" integer NOT NULL DEFAULT 0;
                ALTER TABLE ""Practices"" ADD COLUMN IF NOT EXISTS ""CompletedAt"" timestamp with time zone NULL;

                ALTER TABLE ""PracticeActivities"" RENAME COLUMN ""PracticeId"" TO ""GoalId"";
                ALTER TABLE ""PracticeCheckIns"" RENAME COLUMN ""PracticeId"" TO ""GoalId"";

                ALTER TABLE ""PracticeActivities"" RENAME TO ""GoalActivities"";
                ALTER TABLE ""PracticeCheckIns"" RENAME TO ""GoalCheckIns"";
                ALTER TABLE ""Practices"" RENAME TO ""Goals"";

                CREATE TABLE IF NOT EXISTS ""ConnectionDates"" (
                    ""Id"" uuid NOT NULL PRIMARY KEY,
                    ""ConnectionId"" uuid NOT NULL,
                    ""Label"" text NOT NULL,
                    ""Date"" date NOT NULL,
                    ""Recurrence"" text NOT NULL DEFAULT 'Yearly',
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""FK_ConnectionDates_Connections""
                        FOREIGN KEY (""ConnectionId"")
                        REFERENCES ""Connections"" (""Id"")
                        ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS ""IX_ConnectionDates_ConnectionId""
                    ON ""ConnectionDates"" (""ConnectionId"");

                INSERT INTO ""ConnectionDates"" (""Id"", ""ConnectionId"", ""Label"", ""Date"", ""Recurrence"", ""CreatedAt"", ""UpdatedAt"")
                SELECT ""Id"", ""ConnectionId"", ""Label"", ""Date"",
                       CASE WHEN ""Recurrence"" = 'Yearly' THEN 'Yearly' ELSE 'Once' END,
                       ""CreatedAt"", ""CreatedAt""
                FROM ""Reminders"" WHERE ""ConnectionId"" IS NOT NULL;

                DROP TABLE IF EXISTS ""Reminders"";
            ");
        }
    }
}
