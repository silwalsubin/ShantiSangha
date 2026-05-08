using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    public partial class AddBirthDetailShares : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""BirthDetailShares"" (
                    ""Id"" uuid NOT NULL,
                    ""GrantorUserId"" uuid NOT NULL,
                    ""GranteeUserId"" uuid NOT NULL,
                    ""GrantedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_BirthDetailShares"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_BirthDetailShares_GrantorUserId_GranteeUserId""
                    ON ""BirthDetailShares"" (""GrantorUserId"", ""GranteeUserId"");
                CREATE INDEX IF NOT EXISTS ""IX_BirthDetailShares_GranteeUserId""
                    ON ""BirthDetailShares"" (""GranteeUserId"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""BirthDetailShares"";");
        }
    }
}
