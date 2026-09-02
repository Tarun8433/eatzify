import { MigrationInterface, QueryRunner } from 'typeorm';

/// Append-only audit of every profile and health-profile field change (D-73).
///
/// `profile` is overwritten in place, so before this the previous value of a name, a weight or a
/// meal count was simply gone. Nothing back-fills: rows exist from this migration onward, and an
/// empty history means "not recorded", never "never changed".
export class AddProfileChangeAudit1756000900000 implements MigrationInterface {
  name = 'AddProfileChangeAudit1756000900000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "profile_change" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "entity" character varying NOT NULL,
        "field" character varying NOT NULL,
        "oldValue" text,
        "newValue" text,
        "changedByUserId" integer NOT NULL,
        "source" character varying NOT NULL,
        "changedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_profile_change" PRIMARY KEY ("id"),
        CONSTRAINT "FK_profile_change_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
    // The two questions this table exists to answer: "what has this user changed lately" and
    // "how many times has this user changed THIS field".
    await queryRunner.query(
      `CREATE INDEX "IDX_profile_change_user_date" ON "profile_change" ("userId", "changedAt")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_profile_change_user_field" ON "profile_change" ("userId", "field")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX "public"."IDX_profile_change_user_field"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_profile_change_user_date"`,
    );
    await queryRunner.query(`DROP TABLE "profile_change"`);
  }
}
