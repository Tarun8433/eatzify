import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/12 §2 and §4. What a partner earned, and at what rate.
 *
 * **Append only.** A refund does not edit the entry it reverses — it inserts a negative one that
 * points at it (docs/12 §3: "Commission entry reversed (offsetting entry, never a delete)"). A
 * ledger you can edit is a ledger nobody can reconcile.
 *
 * **Rates are a versioned table, not literals.** docs/12 §2: "Rates live in a rate table, never
 * hardcoded, and are versioned so a historical entry can always be recomputed." The entry stores
 * the basis points it was written at, so a rate change next year cannot silently restate last
 * year's earnings.
 *
 * ⚠ The seeded rates are docs/12 §2's RECOMMENDED structure and have not been signed off. They are
 * what the doc proposes, not what anyone has agreed to pay. Confirm before real money moves.
 */
export class AddCommissionLedger1757300100000 implements MigrationInterface {
  name = 'AddCommissionLedger1757300100000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "commission_rate" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "version" text NOT NULL,
        "tier" text NOT NULL,
        "kind" text NOT NULL,
        "rateBps" integer NOT NULL,
        "renewalMonthsCap" integer,
        "effectiveFrom" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_commission_rate" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_commission_rate_cell" UNIQUE ("version", "tier", "kind"),
        CONSTRAINT "CHK_commission_rate_kind"
          CHECK ("kind" IN ('first_purchase', 'renewal')),
        CONSTRAINT "CHK_commission_rate_bps"
          CHECK ("rateBps" >= 0 AND "rateBps" <= 10000)
      )
    `);

    // docs/12 §2's table. Basis points, never a percentage as a float (rule 3's spirit).
    await queryRunner.query(`
      INSERT INTO "commission_rate" ("version", "tier", "kind", "rateBps", "renewalMonthsCap")
      VALUES
        ('v1', 'BASIC', 'first_purchase', 2500, NULL),
        ('v1', 'BASIC', 'renewal',        1000, 12),
        ('v1', 'PRO',   'first_purchase', 3000, NULL),
        ('v1', 'PRO',   'renewal',        1200, 12)
    `);

    await queryRunner.query(`
      CREATE TABLE "commission_entry" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "partnerUserId" integer NOT NULL,
        "clientUserId" integer NOT NULL,
        "paymentOrderId" uuid NOT NULL,
        "kind" text NOT NULL,
        "rateVersion" text NOT NULL,
        "rateBps" integer NOT NULL,
        "grossPaise" bigint NOT NULL,
        "netPaise" bigint NOT NULL,
        "amountPaise" bigint NOT NULL,
        "status" text NOT NULL DEFAULT 'accrued',
        "periodMonth" text NOT NULL,
        "holdUntil" TIMESTAMP WITH TIME ZONE,
        "reversesId" uuid,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_commission_entry" PRIMARY KEY ("id"),
        CONSTRAINT "FK_commission_entry_partner" FOREIGN KEY ("partnerUserId")
          REFERENCES "user"("id"),
        CONSTRAINT "FK_commission_entry_order" FOREIGN KEY ("paymentOrderId")
          REFERENCES "payment_order"("id"),
        CONSTRAINT "FK_commission_entry_reverses" FOREIGN KEY ("reversesId")
          REFERENCES "commission_entry"("id"),
        CONSTRAINT "CHK_commission_entry_kind"
          CHECK ("kind" IN ('first_purchase', 'renewal', 'bonus', 'reversal')),
        CONSTRAINT "CHK_commission_entry_status"
          CHECK ("status" IN ('accrued', 'payable', 'paid', 'reversed')),
        CONSTRAINT "CHK_commission_entry_period"
          CHECK ("periodMonth" ~ '^[0-9]{4}-[0-9]{2}$')
      )
    `);

    // One entry per order per partner. A webhook Cashfree retries must not pay twice.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_commission_entry_order" ON "commission_entry" ("paymentOrderId")
       WHERE "kind" <> 'reversal'`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_commission_entry_partner_period" ON "commission_entry" ("partnerUserId", "periodMonth")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "commission_entry"`);
    await queryRunner.query(`DROP TABLE "commission_rate"`);
  }
}
