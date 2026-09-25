import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/02 FR-5.5 and docs/09 §6: in-app chat between a coach and their client.
 *
 * The pair IS the thread — a coach and a client have one conversation — so there is no thread
 * table, only the two ids that would have been in it.
 *
 * Every read and write is still gated on a live grant that includes the `chat` scope (docs/10 §3).
 * The table holds no scope of its own: a permission stored twice is a permission that drifts.
 */
export class AddMessage1757800000000 implements MigrationInterface {
  name = 'AddMessage1757800000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "message" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "coachUserId" integer NOT NULL,
        "clientUserId" integer NOT NULL,
        "senderUserId" integer NOT NULL,
        "body" text NOT NULL,
        "readAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_message" PRIMARY KEY ("id"),
        CONSTRAINT "FK_message_coach"
          FOREIGN KEY ("coachUserId") REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_message_client"
          FOREIGN KEY ("clientUserId") REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_message_sender"
          FOREIGN KEY ("senderUserId") REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    // The one query the chat runs: this thread, newest first.
    await queryRunner.query(`
      CREATE INDEX "IDX_message_thread"
        ON "message" ("coachUserId", "clientUserId", "createdAt")
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_message_thread"`);
    await queryRunner.query(`DROP TABLE "message"`);
  }
}
