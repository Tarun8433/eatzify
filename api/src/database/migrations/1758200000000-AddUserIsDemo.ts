import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * `.claude/rules/database.md`: "`is_demo BOOLEAN` on every table with user-visible content. Metrics
 * exclude it." docs/08 §10 says the same about the rollup.
 *
 * One column on `user`, not one per table (D-230). Everything with user-visible content in this
 * schema hangs off a user — diaries, plans, subscriptions, tickets, applications — so a flag on the
 * person answers the question for all of them, and there is no way for two tables to disagree about
 * whether the same account is real.
 *
 * Defaults to false, so every existing row is real until somebody says otherwise: a seeded box
 * marks its own accounts, and a production box has none.
 */
export class AddUserIsDemo1758200000000 implements MigrationInterface {
  name = 'AddUserIsDemo1758200000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "user" ADD COLUMN "isDemo" boolean NOT NULL DEFAULT false`,
    );
    // Partial: the interesting rows are the few that are true, and the metrics query asks for
    // exactly those.
    await queryRunner.query(
      `CREATE INDEX "IDX_user_is_demo" ON "user" ("isDemo") WHERE "isDemo" = true`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_user_is_demo"`);
    await queryRunner.query(`ALTER TABLE "user" DROP COLUMN "isDemo"`);
  }
}
