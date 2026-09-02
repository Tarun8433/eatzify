import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddSubscriptionTable1756000700000 implements MigrationInterface {
  name = 'AddSubscriptionTable1756000700000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "subscription" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "tier" character varying NOT NULL DEFAULT 'FREE',
        "status" character varying NOT NULL DEFAULT 'active',
        "currentPeriodEnd" TIMESTAMP WITH TIME ZONE,
        "providerRef" character varying,
        "provider" character varying,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_subscription" PRIMARY KEY ("id"),
        CONSTRAINT "FK_subscription_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
    // One subscription per user: the lifecycle moves through the row rather than adding one per
    // state, so "what is this person entitled to right now" stays a single lookup.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_subscription_user" ON "subscription" ("userId")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_subscription_user"`);
    await queryRunner.query(`DROP TABLE "subscription"`);
  }
}
