import { MigrationInterface, QueryRunner } from 'typeorm';

/// D-265: personal offers — one special price for one person, reached by an opaque link code.
///
/// The channel rule is in the database as well as the service: a Play offer has all three Play ids
/// and no amount, a Cashfree offer has a positive amount and no Play ids. `payment_order` gains the
/// offer a Cashfree order redeems — nullable, so every existing row and every plain checkout is
/// untouched (expand only).
export class PersonalOffers1759800000000 implements MigrationInterface {
  name = 'PersonalOffers1759800000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "personal_offer" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "code" character varying NOT NULL,
        "userId" integer NOT NULL,
        "tier" character varying NOT NULL,
        "duration" character varying NOT NULL,
        "channel" character varying NOT NULL,
        "playProductId" character varying,
        "playBasePlanId" character varying,
        "playOfferId" character varying,
        "amountPaise" bigint,
        "note" character varying(200),
        "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "usedAt" TIMESTAMP WITH TIME ZONE,
        "revokedAt" TIMESTAMP WITH TIME ZONE,
        "createdByUserId" integer NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_personal_offer" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_personal_offer_code" UNIQUE ("code"),
        CONSTRAINT "FK_personal_offer_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "CHK_personal_offer_tier" CHECK ("tier" IN ('BASIC', 'PRO')),
        CONSTRAINT "CHK_personal_offer_duration" CHECK ("duration" IN ('1M', '3M', '6M', '12M')),
        CONSTRAINT "CHK_personal_offer_channel" CHECK (
          ("channel" = 'play'
            AND "playProductId" IS NOT NULL AND "playBasePlanId" IS NOT NULL
            AND "playOfferId" IS NOT NULL AND "amountPaise" IS NULL)
          OR ("channel" = 'cashfree'
            AND "amountPaise" > 0 AND "playProductId" IS NULL
            AND "playBasePlanId" IS NULL AND "playOfferId" IS NULL)
        )
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_personal_offer_user" ON "personal_offer" ("userId", "createdAt")`,
    );

    await q.query(`ALTER TABLE "payment_order" ADD "personalOfferId" uuid`);
    await q.query(`
      ALTER TABLE "payment_order" ADD CONSTRAINT "FK_payment_order_personal_offer"
        FOREIGN KEY ("personalOfferId") REFERENCES "personal_offer"("id") ON DELETE SET NULL
    `);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(
      `ALTER TABLE "payment_order" DROP CONSTRAINT "FK_payment_order_personal_offer"`,
    );
    await q.query(`ALTER TABLE "payment_order" DROP COLUMN "personalOfferId"`);
    await q.query(`DROP TABLE "personal_offer"`);
  }
}
