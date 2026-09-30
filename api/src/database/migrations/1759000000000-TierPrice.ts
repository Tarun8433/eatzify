import { MigrationInterface, QueryRunner } from 'typeorm';

/// Payments plan, Phase 3: Cashfree prices become rows the admin panel edits, seeded from the
/// prices `src/billing/tiers.ts` shipped with. The grid is fixed — two tiers × four lengths — so the
/// CHECKs refuse any other cell, and a price must be at least ₹1.
export class TierPrice1759000000000 implements MigrationInterface {
  name = 'TierPrice1759000000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "tier_price" (
        "tier" character varying NOT NULL,
        "duration" character varying NOT NULL,
        "pricePaise" bigint NOT NULL,
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_tier_price" PRIMARY KEY ("tier", "duration"),
        CONSTRAINT "CHK_tier_price_tier" CHECK ("tier" IN ('BASIC', 'PRO')),
        CONSTRAINT "CHK_tier_price_duration" CHECK ("duration" IN ('1M', '3M', '6M', '12M')),
        CONSTRAINT "CHK_tier_price_min" CHECK ("pricePaise" >= 100)
      )
    `);
    await q.query(`
      INSERT INTO "tier_price" ("tier", "duration", "pricePaise") VALUES
        ('BASIC', '1M', 24900), ('BASIC', '3M', 69900), ('BASIC', '6M', 119900), ('BASIC', '12M', 209900),
        ('PRO', '1M', 64900), ('PRO', '3M', 179900), ('PRO', '6M', 279900), ('PRO', '12M', 499900)
    `);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TABLE "tier_price"`);
  }
}
