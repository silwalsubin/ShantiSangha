using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Identity.Migrations
{
    /// <summary>
    /// Adds the indexes that make user search fast:
    ///   - pg_trgm extension (one-time, database-level) for substring/fuzzy
    ///     search on display names without scanning every row
    ///   - GIN trigram index on Profiles.DisplayName for case-insensitive
    ///     ILIKE '%foo%' queries
    ///   - Lowercased B-tree indexes on Country/State/City for the location
    ///     filter in user search (matches LOWER("Country") = LOWER(@loc))
    /// </summary>
    public partial class AddUserSearchIndexes : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE EXTENSION IF NOT EXISTS pg_trgm;

                CREATE INDEX IF NOT EXISTS ""IX_Profiles_DisplayName_trgm""
                    ON ""Profiles""
                    USING gin (""DisplayName"" gin_trgm_ops);

                CREATE INDEX IF NOT EXISTS ""IX_Profiles_Country_lower""
                    ON ""Profiles"" (LOWER(""Country""));

                CREATE INDEX IF NOT EXISTS ""IX_Profiles_State_lower""
                    ON ""Profiles"" (LOWER(""State""));

                CREATE INDEX IF NOT EXISTS ""IX_Profiles_City_lower""
                    ON ""Profiles"" (LOWER(""City""));
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP INDEX IF EXISTS ""IX_Profiles_DisplayName_trgm"";
                DROP INDEX IF EXISTS ""IX_Profiles_Country_lower"";
                DROP INDEX IF EXISTS ""IX_Profiles_State_lower"";
                DROP INDEX IF EXISTS ""IX_Profiles_City_lower"";
                -- pg_trgm extension is left in place: dropping a database-level
                -- extension on rollback is risky if other migrations / tables
                -- depend on it. Leave it for the operator to clean up if truly
                -- needed.
            ");
        }
    }
}
