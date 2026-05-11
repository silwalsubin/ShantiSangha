using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddUserPortfolioPositions : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""UserPortfolioPositions"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Ticker"" varchar(16) NOT NULL,
                    ""Shares"" numeric(18,6) NOT NULL,
                    ""CostBasis"" numeric(18,4) NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_UserPortfolioPositions"" PRIMARY KEY (""Id"")
                );

                CREATE INDEX IF NOT EXISTS ""IX_UserPortfolioPositions_UserId""
                    ON ""UserPortfolioPositions"" (""UserId"");

                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_UserPortfolioPositions_UserId_Ticker""
                    ON ""UserPortfolioPositions"" (""UserId"", ""Ticker"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""UserPortfolioPositions"";");
        }
    }
}
