using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// Adds `ConnectionAttachments` — owner-private keepsakes (photos,
    /// videos, files) attached to each Connection. FK cascades from
    /// Connections so removing a connection drops the rows; the S3
    /// cleanup happens in the service layer because the migration can't
    /// reach the bucket. Indexed on ConnectionId for the per-connection
    /// list query and OwnerUserId for owner-scoped sweeps.
    public partial class AddConnectionAttachments : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""ConnectionAttachments"" (
                    ""Id"" uuid NOT NULL PRIMARY KEY,
                    ""ConnectionId"" uuid NOT NULL,
                    ""OwnerUserId"" uuid NOT NULL,
                    ""ObjectKey"" text NOT NULL,
                    ""ContentType"" text NOT NULL,
                    ""ByteSize"" bigint NOT NULL,
                    ""FileName"" text NOT NULL,
                    ""Kind"" text NOT NULL,
                    ""Caption"" text NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""FK_ConnectionAttachments_Connections""
                        FOREIGN KEY (""ConnectionId"")
                        REFERENCES ""Connections"" (""Id"")
                        ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS ""IX_ConnectionAttachments_ConnectionId""
                    ON ""ConnectionAttachments"" (""ConnectionId"");

                CREATE INDEX IF NOT EXISTS ""IX_ConnectionAttachments_OwnerUserId""
                    ON ""ConnectionAttachments"" (""OwnerUserId"");
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""ConnectionAttachments"";
            ");
        }
    }
}
