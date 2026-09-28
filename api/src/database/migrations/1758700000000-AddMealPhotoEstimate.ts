import { MigrationInterface, QueryRunner } from 'typeorm';

/// D-240: a scanned plate is logged as ONE entry with the model's nutrition estimate and the user's
/// own photo.
///
/// `food_log` gains the three micronutrients the add sheet shows (manual entries now copy them too),
/// the path to a private meal photo, and `estimated`, so every screen can say an AI figure is one.
/// `food_scan` keeps the pending estimate and photo between "scan" and "yes", and which entry it
/// became.
export class AddMealPhotoEstimate1758700000000 implements MigrationInterface {
  name = 'AddMealPhotoEstimate1758700000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      ALTER TABLE "food_log"
        ADD "sodiumMg" numeric(8,1),
        ADD "addedSugarG" numeric(6,1),
        ADD "saturatedFatG" numeric(6,1),
        ADD "photoPath" character varying,
        ADD "estimated" boolean NOT NULL DEFAULT false
    `);
    await q.query(`
      ALTER TABLE "food_scan"
        ADD "photoPath" character varying,
        ADD "estimate" jsonb,
        ADD "foodLogId" uuid,
        ADD CONSTRAINT "FK_food_scan_food_log" FOREIGN KEY ("foodLogId")
          REFERENCES "food_log"("id") ON DELETE SET NULL
    `);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`
      ALTER TABLE "food_scan"
        DROP CONSTRAINT "FK_food_scan_food_log",
        DROP COLUMN "foodLogId",
        DROP COLUMN "estimate",
        DROP COLUMN "photoPath"
    `);
    await q.query(`
      ALTER TABLE "food_log"
        DROP COLUMN "estimated",
        DROP COLUMN "photoPath",
        DROP COLUMN "saturatedFatG",
        DROP COLUMN "addedSugarG",
        DROP COLUMN "sodiumMg"
    `);
  }
}
