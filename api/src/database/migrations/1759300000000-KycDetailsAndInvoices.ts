import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Payments plan, Phase 6 (D-255).
 *
 * 1. `partner_kyc` gains what an admin needs to actually send money: account holder name, IFSC, and
 *    the full PAN and account number SEALED (AES-256-GCM, key outside the database). The last-four
 *    columns stay for display. Nullable, because rows written before this have none.
 * 2. `invoice`: GST tax invoices and credit notes for Cashfree sales. Numbered consecutively per
 *    financial year and kind (GST rule 46: unique, consecutive, ≤ 16 characters), from
 *    `invoice_sequence` so two payments at once can never take the same number.
 */
export class KycDetailsAndInvoices1759300000000 implements MigrationInterface {
  name = 'KycDetailsAndInvoices1759300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "partner_kyc"
        ADD "holderName" text,
        ADD "ifsc" text,
        ADD "panSealed" text,
        ADD "accountSealed" text,
        ADD CONSTRAINT "CHK_partner_kyc_ifsc" CHECK ("ifsc" IS NULL OR "ifsc" ~ '^[A-Z]{4}0[A-Z0-9]{6}$')
    `);

    await queryRunner.query(`
      CREATE TABLE "invoice_sequence" (
        "fiscalYear" text NOT NULL,
        "kind" text NOT NULL,
        "next" integer NOT NULL DEFAULT 1,
        CONSTRAINT "PK_invoice_sequence" PRIMARY KEY ("fiscalYear", "kind")
      )
    `);

    await queryRunner.query(`
      CREATE TABLE "invoice" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "number" text NOT NULL,
        "kind" text NOT NULL,
        "fiscalYear" text NOT NULL,
        "userId" integer NOT NULL,
        "paymentOrderId" uuid NOT NULL,
        "refersToId" uuid,
        "issuedAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "description" text NOT NULL,
        "sacCode" text NOT NULL,
        "sellerGstin" text NOT NULL,
        "sellerLegalName" text NOT NULL,
        "sellerAddress" text NOT NULL,
        "sellerStateCode" text NOT NULL,
        "placeOfSupply" text NOT NULL,
        "rateBps" integer NOT NULL,
        "taxablePaise" bigint NOT NULL,
        "cgstPaise" bigint NOT NULL,
        "sgstPaise" bigint NOT NULL,
        "igstPaise" bigint NOT NULL,
        "totalPaise" bigint NOT NULL,
        CONSTRAINT "PK_invoice" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_invoice_number" UNIQUE ("number"),
        CONSTRAINT "UQ_invoice_order_kind" UNIQUE ("paymentOrderId", "kind"),
        CONSTRAINT "FK_invoice_user" FOREIGN KEY ("userId") REFERENCES "user"("id"),
        CONSTRAINT "FK_invoice_order" FOREIGN KEY ("paymentOrderId") REFERENCES "payment_order"("id"),
        CONSTRAINT "FK_invoice_refers" FOREIGN KEY ("refersToId") REFERENCES "invoice"("id"),
        CONSTRAINT "CHK_invoice_kind" CHECK ("kind" IN ('invoice', 'credit_note')),
        CONSTRAINT "CHK_invoice_number_len" CHECK (length("number") <= 16),
        CONSTRAINT "CHK_invoice_sum"
          CHECK ("totalPaise" = "taxablePaise" + "cgstPaise" + "sgstPaise" + "igstPaise"),
        CONSTRAINT "CHK_invoice_credit_refers"
          CHECK (("kind" = 'credit_note') = ("refersToId" IS NOT NULL))
      )
    `);
    await queryRunner.query(
      `CREATE INDEX "IDX_invoice_user" ON "invoice" ("userId", "issuedAt")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "invoice"`);
    await queryRunner.query(`DROP TABLE "invoice_sequence"`);
    await queryRunner.query(`
      ALTER TABLE "partner_kyc"
        DROP CONSTRAINT "CHK_partner_kyc_ifsc",
        DROP COLUMN "accountSealed",
        DROP COLUMN "panSealed",
        DROP COLUMN "ifsc",
        DROP COLUMN "holderName"
    `);
  }
}
