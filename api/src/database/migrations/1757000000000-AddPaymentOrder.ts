import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/11 §5. One row per attempt to pay, including the attempts that fail.
 *
 * `amountPaise` is BIGINT because `api/CLAUDE.md` rule 3 forbids float money, and the partial
 * unique index on `idempotencyKey` is what makes a retried checkout return the first order rather
 * than open a second one.
 */
export class AddPaymentOrder1757000000000 implements MigrationInterface {
  name = 'AddPaymentOrder1757000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "payment_order" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "cashfreeOrderId" character varying NOT NULL,
        "tier" character varying NOT NULL,
        "duration" character varying NOT NULL,
        "amountPaise" bigint NOT NULL,
        "status" character varying NOT NULL DEFAULT 'created',
        "paymentSessionId" character varying,
        "idempotencyKey" character varying,
        "paidAt" TIMESTAMP WITH TIME ZONE,
        "failureReason" character varying,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_payment_order" PRIMARY KEY ("id"),
        CONSTRAINT "FK_payment_order_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "CHK_payment_order_status"
          CHECK ("status" IN ('created', 'paid', 'failed')),
        CONSTRAINT "CHK_payment_order_amount" CHECK ("amountPaise" > 0)
      )
    `);

    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_payment_order_cashfree_id" ON "payment_order" ("cashfreeOrderId")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_payment_order_user" ON "payment_order" ("userId")`,
    );
    // Partial, so the many orders with no key do not collide with each other.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_payment_order_idempotency" ON "payment_order" ("idempotencyKey") WHERE "idempotencyKey" IS NOT NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "payment_order"`);
  }
}
