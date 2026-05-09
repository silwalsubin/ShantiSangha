using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// Adds `PrivateAvatarKey` to `Connections` — the S3 object key for an
    /// owner-private "my version" avatar of the linked person. Nullable
    /// because most connections won't have one; the iOS layer falls back
    /// to the linked Person's public avatar (or initials) when null.
    /// S3 cleanup on row delete is handled in the service layer; this
    /// migration just adds the column.
    public partial class AddConnectionPrivateAvatar : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Connections""
                ADD COLUMN IF NOT EXISTS ""PrivateAvatarKey"" text NULL;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Connections""
                DROP COLUMN IF EXISTS ""PrivateAvatarKey"";
            ");
        }
    }
}
