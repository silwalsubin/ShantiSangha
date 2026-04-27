using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace ShantiSangha.Friends.Migrations
{
    public partial class AddPersonsAndConnections : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                CREATE TABLE IF NOT EXISTS ""Persons"" (
                    ""Id"" uuid NOT NULL,
                    ""UserId"" uuid NULL,
                    ""DisplayName"" text NOT NULL,
                    ""BirthDate"" date NULL,
                    ""BirthTime"" text NULL,
                    ""BirthPlace"" text NULL,
                    ""PhoneNumber"" text NULL,
                    ""Email"" text NULL,
                    ""Country"" text NULL,
                    ""State"" text NULL,
                    ""City"" text NULL,
                    ""Address"" text NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_Persons"" PRIMARY KEY (""Id"")
                );
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_Persons_UserId""
                    ON ""Persons"" (""UserId"") WHERE ""UserId"" IS NOT NULL;

                CREATE TABLE IF NOT EXISTS ""Connections"" (
                    ""Id"" uuid NOT NULL,
                    ""OwnerUserId"" uuid NOT NULL,
                    ""PersonId"" uuid NOT NULL,
                    ""RelationType"" text NOT NULL,
                    ""CustomRelationLabel"" text NULL,
                    ""Nickname"" text NULL,
                    ""PrivateNotes"" text NULL,
                    ""FriendshipId"" uuid NULL,
                    ""CreatedAt"" timestamp with time zone NOT NULL,
                    ""UpdatedAt"" timestamp with time zone NOT NULL,
                    CONSTRAINT ""PK_Connections"" PRIMARY KEY (""Id""),
                    CONSTRAINT ""FK_Connections_Persons"" FOREIGN KEY (""PersonId"")
                        REFERENCES ""Persons"" (""Id"") ON DELETE CASCADE,
                    CONSTRAINT ""FK_Connections_Friendships"" FOREIGN KEY (""FriendshipId"")
                        REFERENCES ""Friendships"" (""Id"") ON DELETE SET NULL
                );
                CREATE INDEX IF NOT EXISTS ""IX_Connections_OwnerUserId""
                    ON ""Connections"" (""OwnerUserId"");
                CREATE UNIQUE INDEX IF NOT EXISTS ""IX_Connections_Owner_Person""
                    ON ""Connections"" (""OwnerUserId"", ""PersonId"");
                CREATE INDEX IF NOT EXISTS ""IX_Connections_FriendshipId""
                    ON ""Connections"" (""FriendshipId"") WHERE ""FriendshipId"" IS NOT NULL;

                -- Backfill: a Person row for every existing user (idempotent via unique
                -- partial index on UserId — re-runs are safe).
                INSERT INTO ""Persons"" (""Id"", ""UserId"", ""DisplayName"", ""BirthDate"", ""BirthTime"", ""BirthPlace"", ""Country"", ""State"", ""City"", ""CreatedAt"", ""UpdatedAt"")
                SELECT
                    gen_random_uuid(),
                    u.""Id"",
                    COALESCE(p.""DisplayName"", ''),
                    p.""BirthDate"",
                    p.""BirthTime"",
                    p.""BirthPlace"",
                    p.""Country"",
                    p.""State"",
                    p.""City"",
                    now(),
                    now()
                FROM ""Users"" u
                LEFT JOIN ""Profiles"" p ON p.""UserId"" = u.""Id""
                WHERE NOT EXISTS (SELECT 1 FROM ""Persons"" pp WHERE pp.""UserId"" = u.""Id"");

                -- Backfill: two Connection rows per Friendship (one per side),
                -- carrying nickname/notes from FriendshipAnnotations if present.
                WITH per AS (
                    SELECT ""Id"" AS ""PersonId"", ""UserId"" FROM ""Persons"" WHERE ""UserId"" IS NOT NULL
                )
                INSERT INTO ""Connections"" (
                    ""Id"", ""OwnerUserId"", ""PersonId"", ""RelationType"",
                    ""Nickname"", ""PrivateNotes"", ""FriendshipId"", ""CreatedAt"", ""UpdatedAt""
                )
                SELECT
                    gen_random_uuid(), f.""UserAId"", per_b.""PersonId"", 'friend',
                    a_a.""Nickname"", a_a.""PrivateNotes"",
                    f.""Id"", f.""CreatedAt"", f.""CreatedAt""
                FROM ""Friendships"" f
                JOIN per per_b ON per_b.""UserId"" = f.""UserBId""
                LEFT JOIN ""FriendshipAnnotations"" a_a
                    ON a_a.""FriendshipId"" = f.""Id"" AND a_a.""OwnerUserId"" = f.""UserAId""
                ON CONFLICT (""OwnerUserId"", ""PersonId"") DO NOTHING;

                WITH per AS (
                    SELECT ""Id"" AS ""PersonId"", ""UserId"" FROM ""Persons"" WHERE ""UserId"" IS NOT NULL
                )
                INSERT INTO ""Connections"" (
                    ""Id"", ""OwnerUserId"", ""PersonId"", ""RelationType"",
                    ""Nickname"", ""PrivateNotes"", ""FriendshipId"", ""CreatedAt"", ""UpdatedAt""
                )
                SELECT
                    gen_random_uuid(), f.""UserBId"", per_a.""PersonId"", 'friend',
                    a_b.""Nickname"", a_b.""PrivateNotes"",
                    f.""Id"", f.""CreatedAt"", f.""CreatedAt""
                FROM ""Friendships"" f
                JOIN per per_a ON per_a.""UserId"" = f.""UserAId""
                LEFT JOIN ""FriendshipAnnotations"" a_b
                    ON a_b.""FriendshipId"" = f.""Id"" AND a_b.""OwnerUserId"" = f.""UserBId""
                ON CONFLICT (""OwnerUserId"", ""PersonId"") DO NOTHING;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                DROP TABLE IF EXISTS ""Connections"";
                DROP TABLE IF EXISTS ""Persons"";
            ");
        }
    }
}
