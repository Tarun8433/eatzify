import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddUserPhone1756000000000 implements MigrationInterface {
  name = 'AddUserPhone1756000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "user" ADD "phone" character varying`);
    await queryRunner.query(
      `ALTER TABLE "user" ADD CONSTRAINT "UQ_user_phone" UNIQUE ("phone")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_user_phone" ON "user" ("phone")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_user_phone"`);
    await queryRunner.query(
      `ALTER TABLE "user" DROP CONSTRAINT "UQ_user_phone"`,
    );
    await queryRunner.query(`ALTER TABLE "user" DROP COLUMN "phone"`);
  }
}
