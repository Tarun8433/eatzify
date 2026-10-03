import { MigrationInterface, QueryRunner } from 'typeorm';

/// Admin panel plan, Phase B: a refund someone asks for after the 7-day self-serve window
/// (docs/11 §9). One open request per order; the decision, who made it and when stay on the row.
export class RefundRequests1759400000000 implements MigrationInterface {
  name = 'RefundRequests1759400000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "refund_request" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "orderId" uuid NOT NULL,
        "userId" integer NOT NULL,
        "reason" character varying(1000) NOT NULL,
        "status" character varying NOT NULL DEFAULT 'requested',
        "decidedBy" integer,
        "decidedAt" TIMESTAMP WITH TIME ZONE,
        "decisionNote" character varying(1000),
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_refund_request" PRIMARY KEY ("id"),
        CONSTRAINT "FK_refund_request_order" FOREIGN KEY ("orderId")
          REFERENCES "payment_order"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_refund_request_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "CHK_refund_request_status" CHECK ("status" IN ('requested', 'approved', 'rejected'))
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_refund_request_status" ON "refund_request" ("status", "createdAt")`,
    );
    await q.query(
      `CREATE UNIQUE INDEX "UQ_refund_request_open" ON "refund_request" ("orderId") WHERE "status" = 'requested'`,
    );
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TABLE "refund_request"`);
  }
}
