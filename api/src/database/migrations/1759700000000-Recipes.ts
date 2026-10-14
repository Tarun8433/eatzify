import { MigrationInterface, QueryRunner } from 'typeorm';

/// D-263: recipes — dishes made of foods, curated in the admin panel and shown on the Plan tab.
/// No nutrition columns: every figure is derived from the ingredients' food rows.
export class Recipes1759700000000 implements MigrationInterface {
  name = 'Recipes1759700000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "recipe" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "name" character varying NOT NULL,
        "nameHi" character varying,
        "description" text NOT NULL DEFAULT '',
        "steps" text array NOT NULL DEFAULT '{}',
        "slots" text array NOT NULL,
        "servings" integer NOT NULL,
        "status" character varying NOT NULL DEFAULT 'draft',
        "createdByUserId" integer,
        "reviewedByUserId" integer,
        "reviewedAt" TIMESTAMP WITH TIME ZONE,
        "publishedByUserId" integer,
        "publishedAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_recipe" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_recipe_status"
          CHECK ("status" IN ('draft', 'reviewed', 'published', 'retired')),
        CONSTRAINT "CHK_recipe_servings" CHECK ("servings" BETWEEN 1 AND 20),
        CONSTRAINT "CHK_recipe_slots" CHECK (cardinality("slots") > 0)
      )
    `);
    await q.query(`CREATE INDEX "IDX_recipe_name" ON "recipe" ("name")`);
    await q.query(`CREATE INDEX "IDX_recipe_status" ON "recipe" ("status")`);

    await q.query(`
      CREATE TABLE "recipe_ingredient" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "recipeId" uuid NOT NULL,
        "foodId" uuid NOT NULL,
        "grams" numeric(7,1) NOT NULL,
        "position" integer NOT NULL,
        CONSTRAINT "PK_recipe_ingredient" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_recipe_ingredient_grams" CHECK ("grams" > 0),
        CONSTRAINT "UQ_recipe_ingredient_food" UNIQUE ("recipeId", "foodId"),
        CONSTRAINT "FK_recipe_ingredient_recipe" FOREIGN KEY ("recipeId")
          REFERENCES "recipe"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_recipe_ingredient_food" FOREIGN KEY ("foodId")
          REFERENCES "food"("id") ON DELETE RESTRICT
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_recipe_ingredient_recipe" ON "recipe_ingredient" ("recipeId")`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TABLE "recipe_ingredient"`);
    await q.query(`DROP TABLE "recipe"`);
  }
}
