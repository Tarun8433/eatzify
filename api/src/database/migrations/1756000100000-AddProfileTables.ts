import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddProfileTables1756000100000 implements MigrationInterface {
  name = 'AddProfileTables1756000100000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "profile" (
        "id" SERIAL NOT NULL,
        "userId" integer NOT NULL,
        "ageYears" integer NOT NULL,
        "heightCm" integer NOT NULL,
        "weightKg" numeric(5,2) NOT NULL,
        "goalWeightKg" numeric(5,2),
        "sexAtBirth" character varying NOT NULL,
        "goal" character varying NOT NULL,
        "activity" character varying NOT NULL,
        "foodPreference" character varying NOT NULL,
        "mealCount" character varying NOT NULL,
        "lifestyle" character varying NOT NULL,
        "budgetTier" character varying NOT NULL,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_profile" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_profile_userId" UNIQUE ("userId"),
        CONSTRAINT "FK_profile_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "health_profile" (
        "id" SERIAL NOT NULL,
        "userId" integer NOT NULL,
        "version" integer NOT NULL,
        "conditions" text array NOT NULL DEFAULT '{}',
        "allergies" text array NOT NULL DEFAULT '{}',
        "screenedSpecialDiet" boolean,
        "screenedInsulinOrKidney" boolean,
        "screenedEatingDisorder" boolean,
        "gates" text array NOT NULL DEFAULT '{}',
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_health_profile" PRIMARY KEY ("id"),
        CONSTRAINT "FK_health_profile_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_health_profile_user_version" ON "health_profile" ("userId", "version")`,
    );

    await queryRunner.query(`
      CREATE TABLE "consent" (
        "id" SERIAL NOT NULL,
        "userId" integer NOT NULL,
        "type" character varying NOT NULL,
        "granted" boolean NOT NULL,
        "policyVersion" character varying NOT NULL DEFAULT '1.0.0',
        "grantedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_consent" PRIMARY KEY ("id"),
        CONSTRAINT "FK_consent_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "consent"`);
    await queryRunner.query(
      `DROP INDEX "public"."IDX_health_profile_user_version"`,
    );
    await queryRunner.query(`DROP TABLE "health_profile"`);
    await queryRunner.query(`DROP TABLE "profile"`);
  }
}
