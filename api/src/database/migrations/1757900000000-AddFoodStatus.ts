import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/08 §4 and docs/09 §9: a food moves draft → reviewed → published (→ retired), and somebody's
 * name is against each step.
 *
 * The table has carried a single `isVerified` boolean, which cannot tell "nobody has checked this"
 * from "somebody checked it and it is not ready". It also cannot say WHO checked it, and a food's
 * macros end up in somebody's plan.
 *
 * **Expand, not replace** (the database rule): `status` is added and backfilled from `isVerified`,
 * and both are kept in step by the service — publishing sets the flag, retiring clears it — so
 * every existing reader (plan generation, logging, search) keeps working untouched. A later
 * migration drops the flag once those reads move across.
 */
export class AddFoodStatus1757900000000 implements MigrationInterface {
  name = 'AddFoodStatus1757900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "food"
        ADD COLUMN "status" character varying NOT NULL DEFAULT 'draft',
        ADD COLUMN "reviewedByUserId" integer,
        ADD COLUMN "reviewedAt" TIMESTAMP WITH TIME ZONE,
        ADD COLUMN "publishedByUserId" integer,
        ADD COLUMN "publishedAt" TIMESTAMP WITH TIME ZONE
    `);

    // What is live today stays live: the 281 seeded foods are verified and in people's plans.
    await queryRunner.query(`
      UPDATE "food" SET "status" = 'published' WHERE "isVerified" = true
    `);

    await queryRunner.query(`
      ALTER TABLE "food"
        ADD CONSTRAINT "CHK_food_status"
          CHECK ("status" IN ('draft', 'reviewed', 'published', 'retired'))
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_food_status" ON "food" ("status")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_food_status"`);
    await queryRunner.query(
      `ALTER TABLE "food" DROP CONSTRAINT "CHK_food_status"`,
    );
    await queryRunner.query(`
      ALTER TABLE "food"
        DROP COLUMN "publishedAt",
        DROP COLUMN "publishedByUserId",
        DROP COLUMN "reviewedAt",
        DROP COLUMN "reviewedByUserId",
        DROP COLUMN "status"
    `);
  }
}
