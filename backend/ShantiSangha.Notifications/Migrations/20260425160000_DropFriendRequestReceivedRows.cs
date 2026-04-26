using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Notifications.Migrations;

/// <summary>
/// One-time sweep: friend_request_received notifications are no longer
/// produced — pending friend requests live exclusively on the Friends tab
/// "REQUESTS RECEIVED" card (queries /friends/requests/incoming directly).
/// Existing rows of this type are stale duplicates from before the
/// switch — drop them. Other notification types are unaffected.
/// </summary>
public partial class DropFriendRequestReceivedRows : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.Sql(@"
            DELETE FROM ""AppNotifications""
            WHERE ""Type"" = 'friend_request_received';
        ");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // No-op: rows are stale by definition; we don't recreate them.
    }
}
