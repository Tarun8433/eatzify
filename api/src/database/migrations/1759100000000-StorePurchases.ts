import { MigrationInterface, QueryRunner } from 'typeorm';

/// Payments plan, Phase 4: Google Play (and later App Store) purchases.
///
/// - A store purchase is claimed by exactly one subscription row: the unique index is what makes a
///   purchase token replayed from another account a conflict instead of a second free plan.
/// - `payment_order` keeps the User Choice Billing token Play hands the app when someone picks
///   Cashfree, and when the sale was reported back to Google (required within 24 hours).
export class StorePurchases1759100000000 implements MigrationInterface {
  name = 'StorePurchases1759100000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE UNIQUE INDEX "UQ_subscription_store_ref" ON "subscription" ("provider", "providerRef")
      WHERE "provider" IN ('play', 'app_store') AND "providerRef" IS NOT NULL
    `);
    await q.query(
      `ALTER TABLE "payment_order" ADD "externalTransactionToken" character varying`,
    );
    await q.query(
      `ALTER TABLE "payment_order" ADD "externalReportedAt" TIMESTAMP WITH TIME ZONE`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(
      `ALTER TABLE "payment_order" DROP COLUMN "externalReportedAt"`,
    );
    await q.query(
      `ALTER TABLE "payment_order" DROP COLUMN "externalTransactionToken"`,
    );
    await q.query(`DROP INDEX "public"."UQ_subscription_store_ref"`);
  }
}
