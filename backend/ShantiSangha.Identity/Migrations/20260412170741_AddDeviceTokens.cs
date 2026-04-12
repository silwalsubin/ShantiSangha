using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Identity.Migrations
{
    /// <inheritdoc />
    public partial class AddDeviceTokens : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Only create DeviceTokens — other Identity tables (Users, Profiles, SafetyEvents)
            // already exist in prod from before migrations were added to this module.
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""DeviceTokens"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NOT NULL,
                    ""Token"" text NOT NULL,
                    ""Platform"" text NOT NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_DeviceTokens"" PRIMARY KEY (""Id""),
                    CONSTRAINT ""FK_DeviceTokens_Users_UserId"" FOREIGN KEY (""UserId"") REFERENCES ""Users"" (""Id"") ON DELETE CASCADE
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_DeviceTokens_Token"" ON ""DeviceTokens"" (""Token"");
                CREATE INDEX IF NOT EXISTS ""IX_DeviceTokens_UserId"" ON ""DeviceTokens"" (""UserId"");
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(name: "DeviceTokens");
        }
    }
}
