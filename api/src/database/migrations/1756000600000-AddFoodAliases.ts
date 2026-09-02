import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddFoodAliases1756000600000 implements MigrationInterface {
  name = 'AddFoodAliases1756000600000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "food" ADD "aliases" text array NOT NULL DEFAULT '{}'`,
    );
    // Search scans aliases on every keystroke-debounced query; GIN keeps that cheap as the table
    // grows past a few hundred rows.
    await queryRunner.query(
      `CREATE INDEX "IDX_food_aliases" ON "food" USING GIN ("aliases")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_food_aliases"`);
    await queryRunner.query(`ALTER TABLE "food" DROP COLUMN "aliases"`);
  }
}
