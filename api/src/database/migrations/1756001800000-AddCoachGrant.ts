import { MigrationInterface, QueryRunner } from 'typeorm';

/// Consent grants (docs/10 §3) — the thing every coach surface is gated on.
///
/// One row per client/coach pair, unique: a second grant to the same coach would be a second
/// answer to one question, and the one that lost would be invisible.
///
/// Revocation does NOT delete the row (docs/10 §3). It moves to `paused`, so the coach's UI can
/// show "access ended" rather than the last data it cached — deleting the row would leave nothing
/// to distinguish "never had access" from "had it until this morning".
export class AddCoachGrant1756001800000 implements MigrationInterface {
  name = 'AddCoachGrant1756001800000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "coach_grant" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "clientUserId" integer NOT NULL,
        "coachUserId" integer NOT NULL,
        "scopes" text array NOT NULL DEFAULT '{}',
        "status" character varying NOT NULL DEFAULT 'active',
        "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "endedReason" character varying,
        "endedAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_coach_grant" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_coach_grant_pair" UNIQUE ("clientUserId", "coachUserId"),
        CONSTRAINT "CHK_coach_grant_status" CHECK ("status" IN ('active', 'paused')),
        CONSTRAINT "FK_coach_grant_client" FOREIGN KEY ("clientUserId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_coach_grant_coach" FOREIGN KEY ("coachUserId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    // "Which clients may I see" is the query every coach screen opens with.
    await queryRunner.query(
      `CREATE INDEX "IDX_coach_grant_coach" ON "coach_grant" ("coachUserId", "status")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "coach_grant"`);
  }
}
