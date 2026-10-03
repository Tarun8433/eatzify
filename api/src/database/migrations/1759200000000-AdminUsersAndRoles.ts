import { MigrationInterface, QueryRunner } from 'typeorm';

/// Admin panel plan, Phase A.
///
/// - Staff roles: `finance` (9) and `content` (10) join the eight in docs/10 §1. Inserted here, not
///   only by the dev seed, so production has every role a staff account can be given.
/// - `status` 3 is `blocked`. `user_block` keeps who blocked whom, why, until when, and who lifted
///   it — one row per block, never edited away, so a person's history survives an unblock.
/// - `user.lastLoginAt` answers "when were they last in".
export class AdminUsersAndRoles1759200000000 implements MigrationInterface {
  name = 'AdminUsersAndRoles1759200000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      INSERT INTO "role" ("id", "name") VALUES
        (1, 'Admin'), (2, 'User'), (3, 'Affiliate Partner'), (4, 'Verified Coach'),
        (5, 'Coaching Partner'), (6, 'Partner Organisation'), (7, 'Support'),
        (8, 'Super Admin'), (9, 'Finance'), (10, 'Content')
      ON CONFLICT ("id") DO NOTHING
    `);
    await q.query(`
      INSERT INTO "status" ("id", "name") VALUES (1, 'Active'), (2, 'Inactive'), (3, 'Blocked')
      ON CONFLICT ("id") DO NOTHING
    `);

    await q.query(`
      CREATE TABLE "user_block" (
        "id" SERIAL NOT NULL,
        "userId" integer NOT NULL,
        "reason" character varying NOT NULL,
        "note" character varying(500),
        "blockedBy" integer NOT NULL,
        "blockedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "until" TIMESTAMP WITH TIME ZONE,
        "liftedAt" TIMESTAMP WITH TIME ZONE,
        "liftedBy" integer,
        CONSTRAINT "PK_user_block" PRIMARY KEY ("id"),
        CONSTRAINT "FK_user_block_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "CHK_user_block_reason" CHECK ("reason" IN
          ('spam', 'fraud', 'abuse', 'suspicious', 'policy', 'other')),
        CONSTRAINT "CHK_user_block_until" CHECK ("until" IS NULL OR "until" > "blockedAt")
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_user_block_user" ON "user_block" ("userId", "blockedAt")`,
    );
    // At most one block in force per person.
    await q.query(
      `CREATE UNIQUE INDEX "UQ_user_block_open" ON "user_block" ("userId") WHERE "liftedAt" IS NULL`,
    );

    await q.query(
      `ALTER TABLE "user" ADD "lastLoginAt" TIMESTAMP WITH TIME ZONE`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE "user" DROP COLUMN "lastLoginAt"`);
    await q.query(`DROP TABLE "user_block"`);
    // Role and status rows stay: users may already point at them.
  }
}
