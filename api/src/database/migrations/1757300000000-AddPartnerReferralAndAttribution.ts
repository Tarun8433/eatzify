import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/12 §3 attribution, and the referral code that feeds it.
 *
 * **Shipped ahead of the commission ledger on purpose.** Attribution is first-touch and locked at
 * signup, so every day it is not capturing is a day of signups that can never be attributed to
 * anyone. The rate maths can be argued about afterwards; the capture cannot be backfilled.
 *
 * `userId` is the PRIMARY KEY of `attribution`, not a plain column. docs/12 §3's "first one wins.
 * No re-attribution ever, including on re-install" is then enforced by the schema rather than by
 * code that has to remember — a second code for the same person is refused by the database.
 */
export class AddPartnerReferralAndAttribution1757300000000 implements MigrationInterface {
  name = 'AddPartnerReferralAndAttribution1757300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "partner_referral" (
        "userId" integer NOT NULL,
        "code" text NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_partner_referral" PRIMARY KEY ("userId"),
        CONSTRAINT "UQ_partner_referral_code" UNIQUE ("code"),
        CONSTRAINT "FK_partner_referral_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "attribution" (
        "userId" integer NOT NULL,
        "partnerUserId" integer NOT NULL,
        "codeUsed" text NOT NULL,
        "channel" text NOT NULL,
        "lockedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_attribution" PRIMARY KEY ("userId"),
        CONSTRAINT "FK_attribution_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_attribution_partner" FOREIGN KEY ("partnerUserId")
          REFERENCES "user"("id"),
        CONSTRAINT "CHK_attribution_channel"
          CHECK ("channel" IN ('code', 'link', 'qr')),
        CONSTRAINT "CHK_attribution_not_self"
          CHECK ("userId" <> "partnerUserId")
      )
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_attribution_partner" ON "attribution" ("partnerUserId")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "attribution"`);
    await queryRunner.query(`DROP TABLE "partner_referral"`);
  }
}
