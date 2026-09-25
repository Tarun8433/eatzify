import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/09 §9: `POST /admin/rule-packs/activate` — super_admin only, requires `reviewed_by` — and
 * the second factor that guards it.
 *
 * Two tables in one migration because they arrive for one reason: the dangerous admin actions now
 * have a record of who did them and a second factor in front of them. Neither has a reader without
 * the other.
 */
export class AddAdminTotpAndRulePackActivation1758100000000 implements MigrationInterface {
  name = 'AddAdminTotpAndRulePackActivation1758100000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "admin_totp" (
        "userId" integer NOT NULL,
        "secret" character varying NOT NULL,
        "confirmedAt" TIMESTAMP WITH TIME ZONE,
        "lastCode" character varying,
        "lastUsedAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_admin_totp" PRIMARY KEY ("userId"),
        CONSTRAINT "FK_admin_totp_user"
          FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "rule_pack_activation" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "version" character varying NOT NULL,
        "activatedByUserId" integer NOT NULL,
        "reviewedByUserId" integer NOT NULL,
        "note" character varying,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_rule_pack_activation" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_rule_pack_two_people"
          CHECK ("reviewedByUserId" <> "activatedByUserId"),
        CONSTRAINT "FK_rule_pack_activated_by"
          FOREIGN KEY ("activatedByUserId") REFERENCES "user"("id"),
        CONSTRAINT "FK_rule_pack_reviewed_by"
          FOREIGN KEY ("reviewedByUserId") REFERENCES "user"("id")
      )
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_rule_pack_activation_at" ON "rule_pack_activation" ("createdAt")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX "public"."IDX_rule_pack_activation_at"`,
    );
    await queryRunner.query(`DROP TABLE "rule_pack_activation"`);
    await queryRunner.query(`DROP TABLE "admin_totp"`);
  }
}
