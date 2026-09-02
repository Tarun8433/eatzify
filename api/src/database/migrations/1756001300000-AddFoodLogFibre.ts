import { MigrationInterface, QueryRunner } from 'typeorm';

/// Fibre eaten (D-136). The plan has always carried a fibre TARGET (the engine's computeFibre);
/// nothing recorded what was eaten against it, because a food_log row copies kcal and the three
/// macros only.
///
/// NULLABLE, not default-0: rows from before this migration genuinely did not record fibre, and a
/// zero would claim "no fibre eaten" where the truth is "not measured". New rows always carry a
/// value, so only days before the deploy under-report — and they under-report by being old, not by
/// lying. Expand-only, per CLAUDE.md rule 8.
export class AddFoodLogFibre1756001300000 implements MigrationInterface {
  name = 'AddFoodLogFibre1756001300000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "food_log" ADD COLUMN "fibreG" numeric(6,1)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "food_log" DROP COLUMN "fibreG"`);
  }
}
