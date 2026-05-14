using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// <summary>
    /// Adds the FriendMessageSuggestions table — assistant-style inline
    /// suggestions parsed out of friend chat messages (e.g. "remind me about
    /// this on Friday"). Backs the Schedule / Not now affordance under each
    /// friend message bubble.
    ///
    /// As originally generated, EF emitted a full-schema Up() because the
    /// FriendsDbContextModelSnapshot was momentarily stale — that crashed
    /// prod on rollout with 42P07 ("ConnectionAttachments" already exists).
    /// This hand-trimmed body only does the genuinely new work and guards
    /// every CREATE with IF NOT EXISTS so a re-run is safe.
    /// </summary>
    public partial class AddFriendMessageSuggestions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""FriendMessageSuggestions"" (
                    ""Id"" uuid NOT NULL PRIMARY KEY,
                    ""FriendMessageId"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Kind"" text NOT NULL,
                    ""Label"" text NOT NULL,
                    ""WhenDate"" date NOT NULL,
                    ""Recurrence"" text NOT NULL,
                    ""DismissedAt"" timestamp with time zone NULL,
                    ""CreatedReminderId"" uuid NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL
                );

                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_FriendMessageSuggestions_FriendMessageId_UserId""
                    ON ""FriendMessageSuggestions"" (""FriendMessageId"", ""UserId"");

                CREATE INDEX IF NOT EXISTS ""IX_FriendMessageSuggestions_UserId_DismissedAt_CreatedReminder~""
                    ON ""FriendMessageSuggestions"" (""UserId"", ""DismissedAt"", ""CreatedReminderId"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""FriendMessageSuggestions"";
            ");
        }
    }
}
