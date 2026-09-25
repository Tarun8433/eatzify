import { MigrationInterface, QueryRunner } from 'typeorm';

/// Coach onboarding (docs/12 §6). One row per applicant.
///
/// `userId` is UNIQUE on purpose: a person is either a partner or applying to be one. A history of
/// attempts belongs in the audit log, and letting a rejected applicant stack rows is how a second
/// application quietly becomes a way around the first decision.
///
/// The document columns hold file ids, not bytes. docs/13 §4 says collect less, and the retention
/// table in §6 has NO row for verification documents — that is a real gap and this migration does
/// not invent an answer to it. Nothing here is purged automatically; the closest analogues are
/// consent records at 7 years and invoices at 8, and picking between them is a legal call.
export class AddCoachApplication1756001600000 implements MigrationInterface {
  name = 'AddCoachApplication1756001600000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "coach_application" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "status" character varying NOT NULL DEFAULT 'draft',
        "agreementAcceptedAt" TIMESTAMP WITH TIME ZONE,
        "agreementVersion" character varying,
        "idDocumentFileId" uuid,
        "qualificationDocumentFileId" uuid,
        "submittedAt" TIMESTAMP WITH TIME ZONE,
        "reviewedAt" TIMESTAMP WITH TIME ZONE,
        "reviewedByUserId" integer,
        "verifiedAttributes" jsonb NOT NULL DEFAULT '[]',
        "rejectionReason" text,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_coach_application" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_coach_application_user" UNIQUE ("userId"),
        CONSTRAINT "CHK_coach_application_status"
          CHECK ("status" IN ('draft', 'submitted', 'verified', 'rejected'))
      )
    `);

    await queryRunner.query(`
      ALTER TABLE "coach_application"
        ADD CONSTRAINT "FK_coach_application_user"
        FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE
    `);

    // The admin queue is "everything waiting for a human", so that is the query to serve.
    await queryRunner.query(
      `CREATE INDEX "IDX_coach_application_status" ON "coach_application" ("status")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "coach_application"`);
  }
}
