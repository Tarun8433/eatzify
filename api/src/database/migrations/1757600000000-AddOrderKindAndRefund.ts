import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/11 §7 and §9. An order now says what it buys and what it gave back.
 *
 * - `kind` — a plain purchase or an upgrade. An upgrade is charged the prorated difference, and the
 *   payment handler has to know which it is before it can decide whether to close the old period.
 * - `creditPaise` — what the proration took off, kept so a receipt can show the arithmetic that was
 *   quoted rather than only the amount charged.
 * - `refundedAt` — docs/11 §9's seven-day window, on the row it belongs to.
 */
export class AddOrderKindAndRefund1757600000000 implements MigrationInterface {
  name = 'AddOrderKindAndRefund1757600000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "payment_order"
        ADD COLUMN "kind" character varying NOT NULL DEFAULT 'purchase',
        ADD COLUMN "creditPaise" bigint NOT NULL DEFAULT 0,
        ADD COLUMN "refundedAt" TIMESTAMP WITH TIME ZONE
    `);

    await queryRunner.query(`
      ALTER TABLE "payment_order"
        ADD CONSTRAINT "CHK_payment_order_kind"
          CHECK ("kind" IN ('purchase', 'upgrade'))
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "payment_order" DROP CONSTRAINT "CHK_payment_order_kind"`,
    );
    await queryRunner.query(`
      ALTER TABLE "payment_order"
        DROP COLUMN "refundedAt",
        DROP COLUMN "creditPaise",
        DROP COLUMN "kind"
    `);
  }
}
