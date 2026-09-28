import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Four rows that are ingredients, not dishes (D-231).
 *
 * The plan search answered a 2,700 kcal day with three cups of raw rava and half a cup of atta:
 * nutritionally exact, and not food. `attr:ingredient` is how the pool knows not to serve a row on
 * its own — they stay searchable and loggable, because people do log "2 tbsp besan".
 *
 * Matched by name because that is what identifies them: `food.id` is a uuid generated at import and
 * differs between every environment. `array_append` is guarded by a `NOT (… = ANY(tags))` so
 * re-running on a database that already has the tag changes nothing.
 */
export class TagIngredientFoods1758300000000 implements MigrationInterface {
  name = 'TagIngredientFoods1758300000000';

  private static readonly NAMES = [
    'Suji / rava (raw)',
    'Wheat flour (atta)',
    'Maida (refined flour)',
    'Besan (gram flour)',
  ];

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `UPDATE "food"
          SET "tags" = array_append("tags", 'attr:ingredient')
        WHERE "name" = ANY($1)
          AND NOT ('attr:ingredient' = ANY("tags"))`,
      [TagIngredientFoods1758300000000.NAMES],
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `UPDATE "food"
          SET "tags" = array_remove("tags", 'attr:ingredient')
        WHERE "name" = ANY($1)`,
      [TagIngredientFoods1758300000000.NAMES],
    );
  }
}
