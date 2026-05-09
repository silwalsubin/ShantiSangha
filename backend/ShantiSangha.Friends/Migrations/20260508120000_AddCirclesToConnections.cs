using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// Replaces the single `RelationType` enum + `CustomRelationLabel`
    /// pair on `Connections` with a free-form `Circles text[]` tag set.
    /// A person can now belong to several circles at once ("Friend",
    /// "Coworker", "Yoga"), and the iOS Circles-tab filter chips
    /// auto-derive from this column rather than a hardcoded enum.
    public partial class AddCirclesToConnections : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Connections""
                    ADD COLUMN IF NOT EXISTS ""Circles"" text[] NOT NULL DEFAULT '{}';

                -- Backfill: every existing row gets a single-element array.
                -- Rows where RelationType='other' AND CustomRelationLabel is set
                -- use the custom label; everything else uses the enum value
                -- with its first letter capitalized so it reads as a proper
                -- circle name ('friend' → 'Friend', 'spouse' → 'Spouse').
                UPDATE ""Connections""
                SET ""Circles"" = CASE
                    WHEN ""RelationType"" = 'other'
                         AND ""CustomRelationLabel"" IS NOT NULL
                         AND length(trim(""CustomRelationLabel"")) > 0
                        THEN ARRAY[trim(""CustomRelationLabel"")]
                    ELSE ARRAY[
                        upper(substring(""RelationType"" from 1 for 1))
                        || lower(substring(""RelationType"" from 2))
                    ]
                END
                WHERE cardinality(""Circles"") = 0;

                ALTER TABLE ""Connections"" DROP COLUMN IF EXISTS ""RelationType"";
                ALTER TABLE ""Connections"" DROP COLUMN IF EXISTS ""CustomRelationLabel"";

                -- GIN index for ARRAY-contains queries — when iOS asks for
                -- 'all connections in the Family circle' the planner can use
                -- this to skip the seq scan.
                CREATE INDEX IF NOT EXISTS ""IX_Connections_Circles""
                    ON ""Connections"" USING GIN (""Circles"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Lossy reverse: collapse the array back to a single relation
            // type. Anything past the first slot is dropped, and unknown
            // labels become 'other' with the original label preserved in
            // CustomRelationLabel.
            migrationBuilder.Sql(@"
                DROP INDEX IF EXISTS ""IX_Connections_Circles"";

                ALTER TABLE ""Connections""
                    ADD COLUMN IF NOT EXISTS ""RelationType"" text NOT NULL DEFAULT 'friend';
                ALTER TABLE ""Connections""
                    ADD COLUMN IF NOT EXISTS ""CustomRelationLabel"" text NULL;

                UPDATE ""Connections""
                SET
                    ""RelationType"" = CASE
                        WHEN cardinality(""Circles"") = 0 THEN 'friend'
                        WHEN lower(""Circles""[1]) IN
                            ('spouse','parent','sibling','child','friend','colleague','other')
                        THEN lower(""Circles""[1])
                        ELSE 'other'
                    END,
                    ""CustomRelationLabel"" = CASE
                        WHEN cardinality(""Circles"") = 0 THEN NULL
                        WHEN lower(""Circles""[1]) IN
                            ('spouse','parent','sibling','child','friend','colleague','other')
                        THEN NULL
                        ELSE ""Circles""[1]
                    END;

                ALTER TABLE ""Connections"" ALTER COLUMN ""RelationType"" DROP DEFAULT;
                ALTER TABLE ""Connections"" DROP COLUMN IF EXISTS ""Circles"";
            ");
        }
    }
}
