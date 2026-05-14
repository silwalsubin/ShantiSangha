using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Agent.Migrations
{
    /// <inheritdoc />
    public partial class AddAgentMessageAttachments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Attachments",
                table: "AgentMessages",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Attachments",
                table: "AgentMessages");
        }
    }
}
