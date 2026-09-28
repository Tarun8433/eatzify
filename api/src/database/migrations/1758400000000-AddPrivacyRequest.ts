import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/13 §9's data-subject rights need somewhere to keep a promise with a date on it: an erasure
 * waits seven days, is warned 48 hours ahead, and then runs. None of that can live in a request
 * handler.
 *
 * The row also survives the erasure it describes — with the account tombstoned, this is what says
 * the right was honoured, and when.
 */
export class AddPrivacyRequest1758400000000 implements MigrationInterface {
  name = 'AddPrivacyRequest1758400000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "privacy_request" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "kind" character varying NOT NULL,
        "status" character varying NOT NULL DEFAULT 'pending',
        "executeAfter" TIMESTAMP WITH TIME ZONE NOT NULL,
        "notifiedAt" TIMESTAMP WITH TIME ZONE,
        "completedAt" TIMESTAMP WITH TIME ZONE,
        "filePath" character varying,
        "downloadExpiresAt" TIMESTAMP WITH TIME ZONE,
        "summary" jsonb NOT NULL DEFAULT '{}',
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_privacy_request" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_privacy_request_kind" CHECK ("kind" IN ('export', 'delete')),
        CONSTRAINT "CHK_privacy_request_status"
          CHECK ("status" IN ('pending', 'notified', 'done', 'cancelled'))
      )
    `);

    // No foreign key to "user", on purpose: the erasure this row records ends with the user row
    // tombstoned, and a cascade would delete the evidence that the request was honoured.
    await queryRunner.query(
      `CREATE INDEX "IDX_privacy_request_user" ON "privacy_request" ("userId")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_privacy_request_due" ON "privacy_request" ("status", "executeAfter")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_privacy_request_due"`);
    await queryRunner.query(`DROP INDEX "public"."IDX_privacy_request_user"`);
    await queryRunner.query(`DROP TABLE "privacy_request"`);
  }
}
