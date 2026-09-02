import { MigrationInterface, QueryRunner } from 'typeorm';

/// A photograph per food, with the credit it is legally served under (D-83).
///
/// `imageAttribution` is not decoration: 229 of the 267 images are CC BY or CC BY-SA, and both
/// require the author to be credited wherever the work is shown. Storing the credit beside the
/// slug is what makes it impossible to serve the picture without it.
///
/// `imageStatus` carries the manifest's own review state. Every image arrived as NEEDS_REVIEW —
/// nobody has confirmed the photograph actually shows the food it is filed under.
export class AddFoodImage1756001100000 implements MigrationInterface {
  name = 'AddFoodImage1756001100000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "food"
        ADD "imageSlug" character varying,
        ADD "imageLicense" character varying,
        ADD "imageAttribution" text,
        ADD "imageSourcePage" text,
        ADD "imageStatus" character varying
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "food"
        DROP COLUMN "imageStatus",
        DROP COLUMN "imageSourcePage",
        DROP COLUMN "imageAttribution",
        DROP COLUMN "imageLicense",
        DROP COLUMN "imageSlug"
    `);
  }
}
