import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddPlanTable1756000200000 implements MigrationInterface {
  name = 'AddPlanTable1756000200000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "plan" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "planDate" date NOT NULL,
        "rulePackVersion" character varying NOT NULL,
        "healthProfileVersion" integer NOT NULL,
        "targets" jsonb,
        "derived" jsonb,
        "mealTargets" jsonb NOT NULL DEFAULT '[]',
        "constraints" jsonb,
        "warnings" text array NOT NULL DEFAULT '{}',
        "gates" text array NOT NULL DEFAULT '{}',
        "trace" jsonb NOT NULL DEFAULT '[]',
        "regenerateReason" character varying,
        "idempotencyKey" character varying,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_plan" PRIMARY KEY ("id"),
        CONSTRAINT "FK_plan_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(
      `CREATE INDEX "IDX_plan_user_date" ON "plan" ("userId", "planDate")`,
    );
    // Partial unique: a retried request reuses its plan, but plans without a key never collide.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_plan_idempotency" ON "plan" ("idempotencyKey") WHERE "idempotencyKey" IS NOT NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_plan_idempotency"`);
    await queryRunner.query(`DROP INDEX "public"."IDX_plan_user_date"`);
    await queryRunner.query(`DROP TABLE "plan"`);
  }
}
