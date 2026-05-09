using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// Adds `ConnectionDates` — the owner-private list of "important
    /// dates" attached to each Connection (birthday, anniversary, day-
    /// we-met). FK cascades from Connections so removing a connection
    /// drops the dates with it; index on ConnectionId for the per-
    /// connection list query.
    public partial class AddConnectionDates : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""ConnectionDates"" (
                    ""Id"" uuid NOT NULL PRIMARY KEY,
                    ""ConnectionId"" uuid NOT NULL,
                    ""Label"" text NOT NULL,
                    ""Date"" date NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""FK_ConnectionDates_Connections""
                        FOREIGN KEY (""ConnectionId"")
                        REFERENCES ""Connections"" (""Id"")
                        ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS ""IX_ConnectionDates_ConnectionId""
                    ON ""ConnectionDates"" (""ConnectionId"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""ConnectionDates"";
            ");
        }
    }
}
