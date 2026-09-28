import { MigrationInterface, QueryRunner } from 'typeorm';

/// The admin surface's two missing pieces (docs/09 §9, docs/08 §8).
///
/// **`audit_log`** — docs/09 §9: "every admin endpoint requires role admin/super_admin AND writes an
/// `audit_log` row when the response contains a health field or PII." Nothing could satisfy that
/// before this table existed, which is the real reason `POST /admin/coaches/{id}/verify` was never
/// built: the accountability it depends on had nowhere to land.
///
/// Append-only, and enforced rather than asked for. docs/08 §8 revokes UPDATE and DELETE; a log an
/// application can rewrite is not evidence of anything. The REVOKE is wrapped because the role it
/// names does not exist in every environment — a dev box created by the boilerplate has no
/// `app_user` — and a migration that dies on a missing grantee blocks the whole chain.
///
/// `actorUserId` is `integer`, not the `UUID` docs/08 §8 writes. The doc describes a users table
/// keyed by uuid; this codebase's `users.id` is an integer and every other foreign key already
/// follows the code (see `coach_application."userId"`). Matching the doc here would make the column
/// unjoinable to the table it points at. Recorded as D-180.
///
/// **`discipline`** — self-declared on the APPLICATION, never on the profile. `Profession` in the
/// Flutter app is deliberately not persisted (docs/13 §4, collect less), and its own comment says
/// "the record that matters is the coach application, which is stored and reviewed". This column is
/// that record: occupational data, collected where it is used, for a purpose the applicant started.
export class AddAuditLogAndDiscipline1756002000000 implements MigrationInterface {
  name = 'AddAuditLogAndDiscipline1756002000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "audit_log" (
        "id" BIGSERIAL NOT NULL,
        "actorUserId" integer,
        "actorRole" text NOT NULL,
        "action" text NOT NULL,
        "subjectUserId" integer,
        "resource" text NOT NULL,
        "meta" jsonb NOT NULL DEFAULT '{}',
        "reason" text,
        "ipHash" text,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_audit_log" PRIMARY KEY ("id")
      )
    `);

    // Reading the log is always "what happened to this person" or "what did this admin do".
    await queryRunner.query(
      `CREATE INDEX "IDX_audit_log_subject" ON "audit_log" ("subjectUserId", "createdAt")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_audit_log_actor" ON "audit_log" ("actorUserId", "createdAt")`,
    );

    // docs/08 §8: append only. Skipped rather than fatal where the role is absent.
    await queryRunner.query(`
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
          REVOKE UPDATE, DELETE ON "audit_log" FROM app_user;
        END IF;
      END $$;
    `);

    await queryRunner.query(
      `ALTER TABLE "coach_application" ADD "discipline" character varying`,
    );
    // Free text would make the count the admin panel exists to show unanswerable — "Dietician",
    // "dietitian" and "Nutrition Coach" are three rows and one person.
    await queryRunner.query(`
      ALTER TABLE "coach_application"
      ADD CONSTRAINT "CHK_coach_application_discipline"
      CHECK ("discipline" IS NULL OR "discipline" IN ('trainer', 'nutritionist', 'doctor', 'other'))
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "coach_application" DROP CONSTRAINT "CHK_coach_application_discipline"`,
    );
    await queryRunner.query(
      `ALTER TABLE "coach_application" DROP COLUMN "discipline"`,
    );
    await queryRunner.query(`DROP INDEX "IDX_audit_log_actor"`);
    await queryRunner.query(`DROP INDEX "IDX_audit_log_subject"`);
    await queryRunner.query(`DROP TABLE "audit_log"`);
  }
}
