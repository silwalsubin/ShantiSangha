using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    /// Drops `Persons.BirthDate`. The Friends module no longer surfaces
    /// a contact birthday — the Connection profile is identity + how-I-
    /// know-them only, and birthdays were redundant noise.
    public partial class DropPersonBirthDate : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Persons"" DROP COLUMN IF EXISTS ""BirthDate"";
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE ""Persons""
                    ADD COLUMN IF NOT EXISTS ""BirthDate"" date NULL;
            ");
        }
    }
}
