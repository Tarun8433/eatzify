import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/12 §4–§5, payments plan Phase 6: paying partners what the ledger says they earned.
 *
 * - `tds_rate` is a dated table so a historical payout is reproducible. **Seeded empty on purpose:**
 *   docs/12 §5 says the section 194H rate comes from the CA, not from code. With no row, the payout
 *   run refuses to prepare anything.
 * - `partner_kyc` holds only what docs/12 §5 allows here: the LAST FOUR of the PAN and bank account.
 *   The full numbers live in the accounting system the payout is actually made from.
 * - `payout` is one partner's balance for one run. A human marks it paid with the bank's UTR;
 *   there are no bank credentials on this server (docs/12 §5: "manual approval, always").
 * - `commission_entry.payoutId` ties each ledger row to the payout that settled it. Additive and
 *   nullable, so older code keeps working (api rule 8).
 */
export class PartnerPayouts1759200000000 implements MigrationInterface {
  name = 'PartnerPayouts1759200000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "tds_rate" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "rateBps" integer NOT NULL,
        "effectiveFrom" TIMESTAMP WITH TIME ZONE NOT NULL,
        "note" text,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_tds_rate" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_tds_rate_from" UNIQUE ("effectiveFrom"),
        CONSTRAINT "CHK_tds_rate_bps" CHECK ("rateBps" >= 0 AND "rateBps" <= 10000)
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "partner_kyc" (
        "partnerUserId" integer NOT NULL,
        "panLast4" text NOT NULL,
        "bankLast4" text NOT NULL,
        "gstin" text,
        "status" text NOT NULL DEFAULT 'pending',
        "bankChangedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "verifiedAt" TIMESTAMP WITH TIME ZONE,
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_partner_kyc" PRIMARY KEY ("partnerUserId"),
        CONSTRAINT "FK_partner_kyc_user" FOREIGN KEY ("partnerUserId") REFERENCES "user"("id"),
        CONSTRAINT "CHK_partner_kyc_status" CHECK ("status" IN ('pending', 'verified', 'rejected')),
        CONSTRAINT "CHK_partner_kyc_pan" CHECK ("panLast4" ~ '^[0-9A-Z]{4}$'),
        CONSTRAINT "CHK_partner_kyc_bank" CHECK ("bankLast4" ~ '^[0-9]{4}$'),
        CONSTRAINT "CHK_partner_kyc_gstin" CHECK ("gstin" IS NULL OR "gstin" ~ '^[0-9A-Z]{15}$')
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "payout" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "partnerUserId" integer NOT NULL,
        "periodMonth" text NOT NULL,
        "grossPaise" bigint NOT NULL,
        "tdsRateBps" integer NOT NULL,
        "tdsPaise" bigint NOT NULL,
        "netPaise" bigint NOT NULL,
        "status" text NOT NULL DEFAULT 'pending_approval',
        "utr" text,
        "approvedBy" integer,
        "paidAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_payout" PRIMARY KEY ("id"),
        CONSTRAINT "FK_payout_partner" FOREIGN KEY ("partnerUserId") REFERENCES "user"("id"),
        CONSTRAINT "FK_payout_approver" FOREIGN KEY ("approvedBy") REFERENCES "user"("id"),
        CONSTRAINT "CHK_payout_status"
          CHECK ("status" IN ('pending_approval', 'paid', 'cancelled')),
        CONSTRAINT "CHK_payout_period" CHECK ("periodMonth" ~ '^[0-9]{4}-[0-9]{2}$'),
        CONSTRAINT "CHK_payout_sum" CHECK ("netPaise" = "grossPaise" - "tdsPaise"),
        CONSTRAINT "CHK_payout_paid_has_utr" CHECK ("status" <> 'paid' OR "utr" IS NOT NULL)
      )
    `);
    // One live payout per partner per run: running the month twice must not pay twice.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_payout_partner_period" ON "payout" ("partnerUserId", "periodMonth")
       WHERE "status" <> 'cancelled'`,
    );

    await queryRunner.query(
      `ALTER TABLE "commission_entry" ADD "payoutId" uuid`,
    );
    await queryRunner.query(
      `ALTER TABLE "commission_entry" ADD CONSTRAINT "FK_commission_entry_payout"
       FOREIGN KEY ("payoutId") REFERENCES "payout"("id")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_commission_entry_payout" ON "commission_entry" ("payoutId")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "IDX_commission_entry_payout"`);
    await queryRunner.query(
      `ALTER TABLE "commission_entry" DROP CONSTRAINT "FK_commission_entry_payout"`,
    );
    await queryRunner.query(
      `ALTER TABLE "commission_entry" DROP COLUMN "payoutId"`,
    );
    await queryRunner.query(`DROP TABLE "payout"`);
    await queryRunner.query(`DROP TABLE "partner_kyc"`);
    await queryRunner.query(`DROP TABLE "tds_rate"`);
  }
}
