import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/13 §5 and docs/14 §6. One message to one person, kept as a row so the app can show a list.
 *
 * `contentClass` is not decoration: docs/13 §5 allows targeting by health condition ONLY for
 * clinical messages, so every notification has to declare which kind it is before anyone can check
 * that rule.
 *
 * `dedupeKey` carries docs/11 §8's renewal schedule. The sweep that sends T-7 runs daily and must
 * be safe to run twice; a unique index is the only version of "once" that a second server cannot
 * race past.
 */
export class AddNotification1757400000000 implements MigrationInterface {
  name = 'AddNotification1757400000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "notification" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "kind" character varying NOT NULL,
        "contentClass" character varying NOT NULL,
        "title" text NOT NULL,
        "body" text NOT NULL,
        "data" jsonb,
        "dedupeKey" character varying,
        "readAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_notification" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_notification_content_class"
          CHECK ("contentClass" IN ('clinical', 'service', 'commercial')),
        CONSTRAINT "FK_notification_user"
          FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_notification_user_created" ON "notification" ("userId", "createdAt")`,
    );

    // Only where there is a key: most notifications are one-offs and may repeat.
    await queryRunner.query(`
      CREATE UNIQUE INDEX "UQ_notification_dedupe"
        ON "notification" ("userId", "dedupeKey")
        WHERE "dedupeKey" IS NOT NULL
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "UQ_notification_dedupe"`);
    await queryRunner.query(`DROP INDEX "IDX_notification_user_created"`);
    await queryRunner.query(`DROP TABLE "notification"`);
  }
}
