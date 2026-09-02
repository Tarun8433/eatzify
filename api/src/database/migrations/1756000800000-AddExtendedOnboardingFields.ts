import { MigrationInterface, QueryRunner } from 'typeorm';

/// Adds the onboarding fields the product asked for that the first contract did not cover:
/// name, declared goal, wake/sleep and meal timings, food dislikes, medications, digestive
/// symptoms, injuries, and the FR-1.3 female-only questions.
///
/// Every column is nullable or defaults to an empty array — existing users onboarded before this
/// migration have no answers for them, and a NOT NULL here would mean either a fabricated default
/// or a failed migration.
export class AddExtendedOnboardingFields1756000800000 implements MigrationInterface {
  name = 'AddExtendedOnboardingFields1756000800000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "profile"
        ADD "name" character varying,
        ADD "goalDeclared" character varying,
        ADD "wakeTime" character varying,
        ADD "sleepTime" character varying,
        ADD "sleepHours" numeric(3,1),
        ADD "breakfastTime" character varying,
        ADD "lunchTime" character varying,
        ADD "eveningSnackTime" character varying,
        ADD "dinnerTime" character varying,
        ADD "foodDislikes" text
    `);
    await queryRunner.query(`
      ALTER TABLE "health_profile"
        ADD "medications" text,
        ADD "digestiveSymptoms" text array NOT NULL DEFAULT '{}',
        ADD "injuries" text array NOT NULL DEFAULT '{}',
        ADD "menstrualRegularity" character varying,
        ADD "pregnantOrBreastfeeding" boolean,
        ADD "heavyBleedingOrPain" boolean,
        ADD "hormonalMedication" boolean
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "health_profile"
        DROP COLUMN "hormonalMedication",
        DROP COLUMN "heavyBleedingOrPain",
        DROP COLUMN "pregnantOrBreastfeeding",
        DROP COLUMN "menstrualRegularity",
        DROP COLUMN "injuries",
        DROP COLUMN "digestiveSymptoms",
        DROP COLUMN "medications"
    `);
    await queryRunner.query(`
      ALTER TABLE "profile"
        DROP COLUMN "foodDislikes",
        DROP COLUMN "dinnerTime",
        DROP COLUMN "eveningSnackTime",
        DROP COLUMN "lunchTime",
        DROP COLUMN "breakfastTime",
        DROP COLUMN "sleepHours",
        DROP COLUMN "sleepTime",
        DROP COLUMN "wakeTime",
        DROP COLUMN "goalDeclared",
        DROP COLUMN "name"
    `);
  }
}
