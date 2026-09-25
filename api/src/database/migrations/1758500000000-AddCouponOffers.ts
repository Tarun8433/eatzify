import { MigrationInterface, QueryRunner } from 'typeorm';

/// D-236: admin-issued offers, and the two columns an order needs to remember one.
export class AddCouponOffers1758500000000 implements MigrationInterface {
  name = 'AddCouponOffers1758500000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "coupon" (
        "code" character varying NOT NULL,
        "percentOff" integer NOT NULL,
        "maxUses" integer NOT NULL,
        "usedCount" integer NOT NULL DEFAULT 0,
        "expiresAt" TIMESTAMP WITH TIME ZONE,
        "active" boolean NOT NULL DEFAULT true,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_coupon_code" PRIMARY KEY ("code")
      )
    `);
    await q.query(
      `ALTER TABLE "payment_order" ADD "couponCode" character varying`,
    );
    await q.query(
      `ALTER TABLE "payment_order" ADD "discountPaise" bigint NOT NULL DEFAULT 0`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE "payment_order" DROP COLUMN "discountPaise"`);
    await q.query(`ALTER TABLE "payment_order" DROP COLUMN "couponCode"`);
    await q.query(`DROP TABLE "coupon"`);
  }
}
