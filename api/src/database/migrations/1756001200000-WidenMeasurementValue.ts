import { MigrationInterface, QueryRunner } from 'typeorm';

/// `numeric(7,2)` could not hold a value the API accepts (D-96).
///
/// `BOUNDS.steps` allows 100000. `numeric(7,2)` allows five digits before the point — 99999.99 —
/// so 100000 passed validation and then threw at the INSERT. The user got a 500 and the day's
/// steps were lost, which is the worst shape a bug can take: rejected AFTER being told the value
/// was fine.
///
/// The column is widened rather than the bound lowered. A 100000-step day is a real day, and the
/// bound is the considered number; 7,2 was chosen when the only kinds were body measurements in
/// kilograms and centimetres, where five digits is generous. Step counts arrived later (D-80) and
/// nothing revisited the column.
///
/// Widening a numeric is a metadata-only change in Postgres — no table rewrite, no lock beyond
/// ACCESS EXCLUSIVE for the catalogue update.
export class WidenMeasurementValue1756001200000 implements MigrationInterface {
  name = 'WidenMeasurementValue1756001200000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "measurement" ALTER COLUMN "value" TYPE numeric(10,2)`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // Only reversible while every stored value still fits. A row above 99999.99 makes this fail,
    // which is correct — silently truncating someone's step count would be worse.
    await queryRunner.query(
      `ALTER TABLE "measurement" ALTER COLUMN "value" TYPE numeric(7,2)`,
    );
  }
}
