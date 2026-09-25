import { MigrationInterface, QueryRunner } from 'typeorm';

/// D-238: who may scan a meal photo, and a count of the scans made.
///
/// `scan_policy` is one row per tier that an admin edits at runtime — the first entitlement that
/// changes without a deploy (billing/tiers.ts names this move). `food_scan` stores NO photo and no
/// result: it is the daily count and an audit trail, nothing a breach could leak about a meal.
export class AddFoodScan1758600000000 implements MigrationInterface {
  name = 'AddFoodScan1758600000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "scan_policy" (
        "tier" character varying NOT NULL,
        "enabled" boolean NOT NULL,
        "dailyLimit" integer NOT NULL,
        "requiresAd" boolean NOT NULL,
        "trialDays" integer,
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_scan_policy_tier" PRIMARY KEY ("tier")
      )
    `);
    // The product owner's starting numbers: FREE scans for its first three days behind an ad,
    // BASIC and PRO scan daily without one.
    await q.query(`
      INSERT INTO "scan_policy" ("tier", "enabled", "dailyLimit", "requiresAd", "trialDays") VALUES
        ('FREE', true, 3, true, 3),
        ('BASIC', true, 10, false, NULL),
        ('PRO', true, 15, false, NULL)
    `);
    await q.query(`
      CREATE TABLE "food_scan" (
        "id" SERIAL NOT NULL,
        "userId" integer NOT NULL,
        "diaryDate" date NOT NULL,
        "matched" boolean NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_food_scan_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_food_scan_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_food_scan_user_day" ON "food_scan" ("userId", "diaryDate")`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP INDEX "IDX_food_scan_user_day"`);
    await q.query(`DROP TABLE "food_scan"`);
    await q.query(`DROP TABLE "scan_policy"`);
  }
}
