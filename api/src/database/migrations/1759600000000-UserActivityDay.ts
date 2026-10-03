import { MigrationInterface, QueryRunner } from 'typeorm';

/// Admin panel plan, Phase D: one row per person per Indian calendar day they used the app,
/// written at sign-in and token refresh. What daily and monthly active users and retention are
/// counted from. No content, only that the day happened.
export class UserActivityDay1759600000000 implements MigrationInterface {
  name = 'UserActivityDay1759600000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "user_activity_day" (
        "userId" integer NOT NULL,
        "day" date NOT NULL,
        CONSTRAINT "PK_user_activity_day" PRIMARY KEY ("userId", "day"),
        CONSTRAINT "FK_user_activity_day_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_user_activity_day_day" ON "user_activity_day" ("day")`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TABLE "user_activity_day"`);
  }
}
