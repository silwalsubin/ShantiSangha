using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Trading.Migrations
{
    /// <summary>
    /// Removes the TradeJournalEntries table introduced by
    /// 20260511140000_AddSellSignalAndJournalAndStopOut. The journal
    /// feature was removed at the user's request before any data
    /// accumulated; the Down migration recreates the table shape so
    /// rolling back doesn't drop unrelated schema.
    /// </summary>
    public partial class DropTradeJournalEntries : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"DROP TABLE IF EXISTS ""TradeJournalEntries"";");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""TradeJournalEntries"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Ticker"" varchar(16) NOT NULL,
                    ""Kind"" varchar(16) NOT NULL,
                    ""Price"" numeric(18,4) NULL,
                    ""Shares"" numeric(18,6) NULL,
                    ""Reason"" varchar(500) NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_TradeJournalEntries"" PRIMARY KEY (""Id"")
                );
                CREATE INDEX IF NOT EXISTS ""IX_TradeJournalEntries_UserId_CreatedAt""
                    ON ""TradeJournalEntries"" (""UserId"", ""CreatedAt"");
            ");
        }
    }
}
