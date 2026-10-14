import { MigrationInterface, QueryRunner } from 'typeorm';

/// D-266: every Google Play / App Store purchase attempt the app saw end, for support. A new table
/// only (expand), so nothing existing changes. No amount, no payment data, no purchase token.
export class StorePurchaseAttempts1759900000000 implements MigrationInterface {
  name = 'StorePurchaseAttempts1759900000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "store_purchase_attempt" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "userId" integer NOT NULL,
        "provider" character varying NOT NULL,
        "productId" character varying(100) NOT NULL,
        "basePlanId" character varying(100),
        "offerId" character varying(100),
        "outcome" character varying NOT NULL,
        "reason" character varying(40),
        "storeCode" character varying(80),
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_store_purchase_attempt" PRIMARY KEY ("id"),
        CONSTRAINT "FK_store_purchase_attempt_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "CHK_store_purchase_attempt_provider"
          CHECK ("provider" IN ('play', 'app_store')),
        CONSTRAINT "CHK_store_purchase_attempt_outcome"
          CHECK ("outcome" IN ('cancelled', 'failed', 'pending', 'purchased', 'refused')),
        CONSTRAINT "CHK_store_purchase_attempt_reason" CHECK (
          "reason" IS NULL OR "reason" IN ('storeUnavailable', 'productUnavailable',
            'alreadyOwned', 'storeBusy', 'storeFailed', 'serverRefused')
        )
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_store_purchase_attempt_created" ON "store_purchase_attempt" ("createdAt")`,
    );
    await q.query(
      `CREATE INDEX "IDX_store_purchase_attempt_user" ON "store_purchase_attempt" ("userId", "createdAt")`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TABLE "store_purchase_attempt"`);
  }
}
