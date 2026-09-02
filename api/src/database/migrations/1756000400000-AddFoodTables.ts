import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddFoodTables1756000400000 implements MigrationInterface {
  name = 'AddFoodTables1756000400000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "food" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "name" character varying NOT NULL,
        "nameHi" character varying,
        "kcal" numeric(7,2) NOT NULL,
        "proteinG" numeric(6,2) NOT NULL,
        "fatG" numeric(6,2) NOT NULL,
        "carbG" numeric(6,2) NOT NULL,
        "fibreG" numeric(6,2) NOT NULL DEFAULT 0,
        "sodiumMg" numeric(8,2) NOT NULL DEFAULT 0,
        "addedSugarG" numeric(6,2) NOT NULL DEFAULT 0,
        "saturatedFatG" numeric(6,2) NOT NULL DEFAULT 0,
        "tags" text array NOT NULL DEFAULT '{}',
        "suitableFor" text array NOT NULL DEFAULT '{}',
        "allergens" text array NOT NULL DEFAULT '{}',
        "costTier" character varying NOT NULL DEFAULT 'medium',
        "source" character varying NOT NULL,
        "sourceRef" character varying,
        "isVerified" boolean NOT NULL DEFAULT false,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_food" PRIMARY KEY ("id")
      )
    `);
    await queryRunner.query(`CREATE INDEX "IDX_food_name" ON "food" ("name")`);

    await queryRunner.query(`
      CREATE TABLE "household_measure" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "foodId" uuid NOT NULL,
        "label" character varying NOT NULL,
        "labelHi" character varying,
        "grams" numeric(7,2) NOT NULL,
        "isDefault" boolean NOT NULL DEFAULT false,
        CONSTRAINT "PK_household_measure" PRIMARY KEY ("id"),
        CONSTRAINT "FK_household_measure_food" FOREIGN KEY ("foodId")
          REFERENCES "food"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_measure_food_label" ON "household_measure" ("foodId", "label")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "household_measure"`);
    await queryRunner.query(`DROP INDEX "public"."IDX_food_name"`);
    await queryRunner.query(`DROP TABLE "food"`);
  }
}
