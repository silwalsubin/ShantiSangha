using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// <inheritdoc />
    public partial class AddFriendMessageSuggestions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ConnectionAttachments",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ConnectionId = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ObjectKey = table.Column<string>(type: "text", nullable: false),
                    ContentType = table.Column<string>(type: "text", nullable: false),
                    ByteSize = table.Column<long>(type: "bigint", nullable: false),
                    FileName = table.Column<string>(type: "text", nullable: false),
                    Kind = table.Column<string>(type: "text", nullable: false),
                    Caption = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ConnectionAttachments", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "FriendInvitations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    InviterUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Token = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    AcceptedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    AcceptedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    RevokedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FriendInvitations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "FriendMessageReactions",
                columns: table => new
                {
                    MessageId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Emoji = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FriendMessageReactions", x => new { x.MessageId, x.UserId });
                });

            migrationBuilder.CreateTable(
                name: "FriendMessages",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FriendshipId = table.Column<Guid>(type: "uuid", nullable: false),
                    SenderUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ReplyToMessageId = table.Column<Guid>(type: "uuid", nullable: true),
                    Kind = table.Column<string>(type: "text", nullable: false),
                    Body = table.Column<string>(type: "text", nullable: true),
                    StorageKey = table.Column<string>(type: "text", nullable: true),
                    DurationMs = table.Column<int>(type: "integer", nullable: true),
                    SentAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ReadAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    EditedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    DeletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FriendMessages", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "FriendMessageSuggestions",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FriendMessageId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "text", nullable: false),
                    Label = table.Column<string>(type: "text", nullable: false),
                    WhenDate = table.Column<DateOnly>(type: "date", nullable: false),
                    Recurrence = table.Column<string>(type: "text", nullable: false),
                    DismissedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedReminderId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FriendMessageSuggestions", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "FriendRequests",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FromUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ToUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Status = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    RespondedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FriendRequests", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "FriendshipAnnotations",
                columns: table => new
                {
                    FriendshipId = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Nickname = table.Column<string>(type: "text", nullable: true),
                    PrivateNotes = table.Column<string>(type: "text", nullable: true),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_FriendshipAnnotations", x => new { x.FriendshipId, x.OwnerUserId });
                });

            migrationBuilder.CreateTable(
                name: "Friendships",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserAId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserBId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Friendships", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Persons",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: true),
                    DisplayName = table.Column<string>(type: "text", nullable: false),
                    PhoneNumber = table.Column<string>(type: "text", nullable: true),
                    Email = table.Column<string>(type: "text", nullable: true),
                    Country = table.Column<string>(type: "text", nullable: true),
                    State = table.Column<string>(type: "text", nullable: true),
                    City = table.Column<string>(type: "text", nullable: true),
                    Address = table.Column<string>(type: "text", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Persons", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Connections",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    PersonId = table.Column<Guid>(type: "uuid", nullable: false),
                    Circles = table.Column<string[]>(type: "text[]", nullable: false),
                    Nickname = table.Column<string>(type: "text", nullable: true),
                    PrivateNotes = table.Column<string>(type: "text", nullable: true),
                    PrivateAvatarKey = table.Column<string>(type: "text", nullable: true),
                    FriendshipId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Connections", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Connections_Persons_PersonId",
                        column: x => x.PersonId,
                        principalTable: "Persons",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ConnectionAttachments_ConnectionId",
                table: "ConnectionAttachments",
                column: "ConnectionId");

            migrationBuilder.CreateIndex(
                name: "IX_ConnectionAttachments_OwnerUserId",
                table: "ConnectionAttachments",
                column: "OwnerUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Connections_FriendshipId",
                table: "Connections",
                column: "FriendshipId");

            migrationBuilder.CreateIndex(
                name: "IX_Connections_OwnerUserId",
                table: "Connections",
                column: "OwnerUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Connections_OwnerUserId_PersonId",
                table: "Connections",
                columns: new[] { "OwnerUserId", "PersonId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Connections_PersonId",
                table: "Connections",
                column: "PersonId");

            migrationBuilder.CreateIndex(
                name: "IX_FriendInvitations_InviterUserId_AcceptedAt_RevokedAt",
                table: "FriendInvitations",
                columns: new[] { "InviterUserId", "AcceptedAt", "RevokedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_FriendInvitations_Token",
                table: "FriendInvitations",
                column: "Token",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_FriendMessages_FriendshipId_SentAt",
                table: "FriendMessages",
                columns: new[] { "FriendshipId", "SentAt" });

            migrationBuilder.CreateIndex(
                name: "IX_FriendMessages_ReplyToMessageId",
                table: "FriendMessages",
                column: "ReplyToMessageId");

            migrationBuilder.CreateIndex(
                name: "IX_FriendMessages_SenderUserId",
                table: "FriendMessages",
                column: "SenderUserId");

            migrationBuilder.CreateIndex(
                name: "IX_FriendMessageSuggestions_FriendMessageId_UserId",
                table: "FriendMessageSuggestions",
                columns: new[] { "FriendMessageId", "UserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_FriendMessageSuggestions_UserId_DismissedAt_CreatedReminder~",
                table: "FriendMessageSuggestions",
                columns: new[] { "UserId", "DismissedAt", "CreatedReminderId" });

            migrationBuilder.CreateIndex(
                name: "IX_FriendRequests_FromUserId_Status_CreatedAt",
                table: "FriendRequests",
                columns: new[] { "FromUserId", "Status", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_FriendRequests_ToUserId_Status_CreatedAt",
                table: "FriendRequests",
                columns: new[] { "ToUserId", "Status", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_FriendshipAnnotations_OwnerUserId",
                table: "FriendshipAnnotations",
                column: "OwnerUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Friendships_UserAId",
                table: "Friendships",
                column: "UserAId");

            migrationBuilder.CreateIndex(
                name: "IX_Friendships_UserAId_UserBId",
                table: "Friendships",
                columns: new[] { "UserAId", "UserBId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Friendships_UserBId",
                table: "Friendships",
                column: "UserBId");

            migrationBuilder.CreateIndex(
                name: "IX_Persons_UserId",
                table: "Persons",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ConnectionAttachments");

            migrationBuilder.DropTable(
                name: "Connections");

            migrationBuilder.DropTable(
                name: "FriendInvitations");

            migrationBuilder.DropTable(
                name: "FriendMessageReactions");

            migrationBuilder.DropTable(
                name: "FriendMessages");

            migrationBuilder.DropTable(
                name: "FriendMessageSuggestions");

            migrationBuilder.DropTable(
                name: "FriendRequests");

            migrationBuilder.DropTable(
                name: "FriendshipAnnotations");

            migrationBuilder.DropTable(
                name: "Friendships");

            migrationBuilder.DropTable(
                name: "Persons");
        }
    }
}
