import { MigrationInterface, QueryRunner } from 'typeorm';

/// Coach invites (docs/09 §6). A coach asking one person to work with them.
///
/// Addressed by PHONE, not by user id, because the person may not have an account yet — which is
/// also the reason the endpoint that creates one must not reveal whether they do (docs/09 §3).
///
/// No unique constraint on the pair: a declined invite and a later, better-timed one are different
/// events, and collapsing them would let a "no" be overwritten into a "not yet asked". The service
/// keeps at most one PENDING invite per pair instead.
export class AddCoachInvite1756001900000 implements MigrationInterface {
  name = 'AddCoachInvite1756001900000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "coach_invite" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "coachUserId" integer NOT NULL,
        "phoneE164" character varying NOT NULL,
        "scopes" text array NOT NULL DEFAULT '{}',
        "status" character varying NOT NULL DEFAULT 'pending',
        "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "respondedAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_coach_invite" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_coach_invite_status"
          CHECK ("status" IN ('pending', 'accepted', 'declined', 'expired')),
        CONSTRAINT "FK_coach_invite_coach" FOREIGN KEY ("coachUserId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    // "What has been sent to this number" is the query a client's inbox runs on every open.
    await queryRunner.query(
      `CREATE INDEX "IDX_coach_invite_phone" ON "coach_invite" ("phoneE164", "status")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_coach_invite_coach" ON "coach_invite" ("coachUserId", "status")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "coach_invite"`);
  }
}
