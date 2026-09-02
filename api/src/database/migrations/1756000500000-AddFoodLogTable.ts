import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddFoodLogTable1756000500000 implements MigrationInterface {
  name = 'AddFoodLogTable1756000500000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "food_log" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "diaryDate" date NOT NULL,
        "slot" character varying NOT NULL,
        "foodId" uuid,
        "customName" character varying,
        "quantityG" numeric(7,1) NOT NULL,
        "measureLabel" character varying,
        "kcal" numeric(7,1) NOT NULL,
        "proteinG" numeric(6,1) NOT NULL,
        "carbG" numeric(6,1) NOT NULL,
        "fatG" numeric(6,1) NOT NULL,
        "source" character varying NOT NULL DEFAULT 'manual',
        "lockedAt" TIMESTAMP WITH TIME ZONE,
        "loggedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_food_log" PRIMARY KEY ("id"),
        CONSTRAINT "FK_food_log_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_food_log_food" FOREIGN KEY ("foodId")
          REFERENCES "food"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE INDEX "IDX_food_log_user_date" ON "food_log" ("userId", "diaryDate")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_food_log_user_date"`);
    await queryRunner.query(`DROP TABLE "food_log"`);
  }
}
