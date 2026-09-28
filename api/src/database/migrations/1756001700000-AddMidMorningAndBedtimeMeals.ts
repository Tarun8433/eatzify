import { MigrationInterface, QueryRunner } from 'typeorm';

/// The two meal slots a five-to-six pattern has and `profile` never had (D-171).
///
/// docs/04 §7 spells the pattern out: breakfast, mid-morning, lunch, evening, dinner and an
/// OPTIONAL bedtime. The table carried four columns, so anyone choosing 5–6 meals was shown the
/// four-meal question and their plan was built around a day they had not described.
///
/// Nullable, like every other clock column: an existing profile genuinely never answered these,
/// and a default would invent an eating occasion the user never mentioned. Expand-only (rule 8).
export class AddMidMorningAndBedtimeMeals1756001700000 implements MigrationInterface {
  name = 'AddMidMorningAndBedtimeMeals1756001700000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "profile" ADD COLUMN "midMorningTime" character varying`,
    );
    await queryRunner.query(
      `ALTER TABLE "profile" ADD COLUMN "bedtimeSnackTime" character varying`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "profile" DROP COLUMN "bedtimeSnackTime"`,
    );
    await queryRunner.query(
      `ALTER TABLE "profile" DROP COLUMN "midMorningTime"`,
    );
  }
}
