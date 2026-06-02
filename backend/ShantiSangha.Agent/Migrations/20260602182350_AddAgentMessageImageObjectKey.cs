using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Agent.Migrations
{
    /// <inheritdoc />
    public partial class AddAgentMessageImageObjectKey : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ImageObjectKey",
                table: "AgentMessages",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ImageObjectKey",
                table: "AgentMessages");
        }
    }
}
