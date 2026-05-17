using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    public partial class AddIbkrAccountAndPositionSource : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""IbkrAccounts"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""IbkrAccountId"" varchar(32) NOT NULL,
                    ""Status"" varchar(16) NOT NULL,
                    ""LinkedAt"" timestamp with time zone NOT NULL,
                    ""LastSyncAt"" timestamp with time zone NULL,
                    ""LastSuccessfulSyncAt"" timestamp with time zone NULL,
                    ""LastErrorMessage"" varchar(512) NULL,
                    ""LastErrorAt"" timestamp with time zone NULL,
                    ""BaseCurrency"" varchar(8) NOT NULL,
                    ""CashBalance"" numeric(18,4) NOT NULL,
                    ""CashBalanceAt"" timestamp with time zone NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_IbkrAccounts"" PRIMARY KEY (""Id"")
                );

                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_IbkrAccounts_UserId""
                    ON ""IbkrAccounts"" (""UserId"");

                ALTER TABLE ""UserPortfolioPositions""
                    ADD COLUMN IF NOT EXISTS ""Source"" varchar(8) NOT NULL DEFAULT 'Manual',
                    ADD COLUMN IF NOT EXISTS ""ExternalAccountId"" varchar(32) NULL,
                    ADD COLUMN IF NOT EXISTS ""ExternalPositionId"" varchar(32) NULL,
                    ADD COLUMN IF NOT EXISTS ""Conid"" bigint NULL;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""UserPortfolioPositions""
                    DROP COLUMN IF EXISTS ""Source"",
                    DROP COLUMN IF EXISTS ""ExternalAccountId"",
                    DROP COLUMN IF EXISTS ""ExternalPositionId"",
                    DROP COLUMN IF EXISTS ""Conid"";

                DROP TABLE IF EXISTS ""IbkrAccounts"";
            ");
        }
    }
}
