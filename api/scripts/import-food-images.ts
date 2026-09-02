import { copyFileSync, existsSync, mkdirSync, readFileSync } from 'fs';
import { basename, join, resolve } from 'path';
import { parse } from 'csv-parse/sync';
import { DataSource } from 'typeorm';
import { AppDataSource } from '../src/database/data-source';

/// Imports the food photographs and the credit each one is served under (D-83).
///
/// Run once per manifest:
///   npx ts-node -r tsconfig-paths/register scripts/import-food-images.ts "<folder>"
///
/// The folder is the one the images arrived in — it must contain `image-manifest.csv` and an
/// `images/` directory. Images are copied into `files/food-images/`, which is what the API serves.
///
/// Matching is by food NAME, because that is the only column the manifest and the food table
/// share. A name that is not in the database is reported, not guessed at: a photograph filed
/// against the wrong food is worse than a food with no photograph, and in a diet app someone may
/// be reading the picture rather than the label.

type ManifestRow = {
  name: string;
  imageSlug: string;
  file: string;
  sourcePage: string;
  license: string;
  attribution: string;
  status: string;
};

const IMAGE_DIR = resolve('files/food-images');

async function main(): Promise<void> {
  const folder = process.argv[2];
  if (!folder) {
    console.error(
      'usage: import-food-images.ts <folder containing image-manifest.csv>',
    );
    process.exit(1);
  }

  const manifestPath = join(folder, 'image-manifest.csv');
  if (!existsSync(manifestPath)) {
    console.error(`no manifest at ${manifestPath}`);
    process.exit(1);
  }

  const rows = parse(readFileSync(manifestPath), {
    columns: true,
    skip_empty_lines: true,
  }) as ManifestRow[];

  mkdirSync(IMAGE_DIR, { recursive: true });

  const source: DataSource = await AppDataSource.initialize();
  const missingFile: string[] = [];
  const unmatched: string[] = [];
  let imported = 0;

  try {
    for (const row of rows) {
      // Rows the collector could not find an image for. Nothing to copy and nothing to record.
      if (!row.file || !row.imageSlug) continue;

      const from = join(folder, row.file);
      if (!existsSync(from)) {
        missingFile.push(row.name);
        continue;
      }

      const filename = basename(row.file);
      copyFileSync(from, join(IMAGE_DIR, filename));

      const result = await source.query(
        `UPDATE "food"
            SET "imageSlug" = $1,
                "imageLicense" = $2,
                "imageAttribution" = $3,
                "imageSourcePage" = $4,
                "imageStatus" = $5
          WHERE "name" = $6`,
        [
          filename,
          row.license || null,
          row.attribution || null,
          row.sourcePage || null,
          row.status || null,
          row.name,
        ],
      );

      // node-postgres puts the row count in the second element for UPDATE.
      const updated = Array.isArray(result) ? Number(result[1] ?? 0) : 0;
      if (updated === 0) {
        unmatched.push(row.name);
        continue;
      }
      imported += 1;
    }
  } finally {
    await source.destroy();
  }

  console.log(`linked   ${imported}`);
  if (missingFile.length > 0) {
    console.log(
      `no file  ${missingFile.length}: ${missingFile.slice(0, 5).join(', ')}…`,
    );
  }
  if (unmatched.length > 0) {
    console.log(
      `no food  ${unmatched.length} (image copied, nothing to attach it to): ` +
        `${unmatched.slice(0, 10).join(', ')}${unmatched.length > 10 ? '…' : ''}`,
    );
  }

  const needsReview = rows.filter((r) => r.status === 'NEEDS_REVIEW').length;
  if (needsReview > 0) {
    console.log(
      `\nNEEDS_REVIEW ${needsReview}. No one has confirmed these photographs show the food they ` +
        `are filed under. Review them before this reaches users.`,
    );
  }
}

void main();
