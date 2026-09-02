import { MigrationInterface, QueryRunner } from 'typeorm';

/// The monthly food budget in rupees (D-78).
///
/// Nullable: `budget_tier` is still the required field and still what the engine plans on, so
/// everyone onboarded before the slider existed keeps a valid profile with no amount recorded.
export class AddBudgetMonthlyInr1756001000000 implements MigrationInterface {
  name = 'AddBudgetMonthlyInr1756001000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "profile" ADD "budgetMonthlyInr" integer`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "profile" DROP COLUMN "budgetMonthlyInr"`,
    );
  }
}
