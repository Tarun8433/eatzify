import { MigrationInterface, QueryRunner } from 'typeorm';

/// The food itself (D-164). `plan` has carried `mealTargets` — how much energy each slot gets —
/// since it existed, and nothing to say what to eat, because engine steps 11 and 13 were unwritten.
///
/// `DEFAULT '[]'` rather than nullable: a plan generated before this column existed genuinely had
/// no meals, and an empty list says exactly that. Null would make every reader decide between "no
/// food chosen" and "not asked", which is the same contract split the fibre column avoided by
/// going the other way (D-136) — there the distinction was real and worth keeping, here it is not.
///
/// Expand-only, per CLAUDE.md rule 8.
export class AddPlanMeals1756001500000 implements MigrationInterface {
  name = 'AddPlanMeals1756001500000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "plan" ADD COLUMN "meals" jsonb NOT NULL DEFAULT '[]'`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "plan" DROP COLUMN "meals"`);
  }
}
