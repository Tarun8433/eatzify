import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/08 §6 and docs/11 §5–§8. What a subscription needs before it can do anything but exist.
 *
 * Until now the row held a tier, a status and a period end. The lifecycle needs more:
 *
 * - `startsAt` and `paidPaise` — docs/11 §7 prorates an upgrade from how much of the paid period
 *   is left, which cannot be worked out from an end date alone.
 * - `autoRenew` and `cancelledAt` — docs/09 §7's cancel "cancels renewal, retains access to
 *   ends_at", so cancelling is not a status change.
 * - `requiresAfa` — docs/11 §8: above ₹15,000 the RBI 2026 framework needs additional factor
 *   authentication on EVERY debit, which is a different renewal path, not a flag on a screen.
 * - `trialEndsAt` — docs/11 §6.
 *
 * **The unique index becomes partial.** docs/11 §7: an upgrade closes the old row and opens a new
 * one, "never mutate the old row". One row per user forever made that impossible, so the index now
 * only forbids a second LIVE subscription — exactly docs/08 §6's `one_live_sub`.
 *
 * `currentPeriodEnd` keeps its name rather than becoming `ends_at`: it is what every caller already
 * reads, and a rename is a separate expand/contract migration with no behaviour in it.
 */
export class AddSubscriptionLifecycle1757500000000 implements MigrationInterface {
  name = 'AddSubscriptionLifecycle1757500000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "subscription"
        ADD COLUMN "startsAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        ADD COLUMN "paidPaise" bigint,
        ADD COLUMN "priceKey" character varying,
        ADD COLUMN "autoRenew" boolean NOT NULL DEFAULT false,
        ADD COLUMN "requiresAfa" boolean NOT NULL DEFAULT false,
        ADD COLUMN "cancelledAt" TIMESTAMP WITH TIME ZONE,
        ADD COLUMN "trialEndsAt" TIMESTAMP WITH TIME ZONE
    `);

    /**
     * Rows that predate the status list. The dev database holds two: tier FREE, status `none`, no
     * period — written by a path that no longer exists. They are not a live subscription in any
     * sense docs/08 §6 defines, so they become history rather than blocking the constraint.
     */
    await queryRunner.query(`
      UPDATE "subscription" SET "status" = 'expired'
      WHERE "status" NOT IN (
        'trialing', 'active', 'past_due', 'grace', 'cancelled', 'expired'
      )
    `);

    await queryRunner.query(`
      ALTER TABLE "subscription"
        ADD CONSTRAINT "CHK_subscription_status" CHECK ("status" IN (
          'trialing', 'active', 'past_due', 'grace', 'cancelled', 'expired'
        ))
    `);

    // docs/08 §6's one_live_sub. A user may have many rows and at most one that is running.
    await queryRunner.query(`DROP INDEX "public"."IDX_subscription_user"`);
    await queryRunner.query(`
      CREATE UNIQUE INDEX "UQ_subscription_live" ON "subscription" ("userId")
        WHERE "status" IN ('trialing', 'active', 'past_due', 'grace')
    `);
    await queryRunner.query(
      `CREATE INDEX "IDX_subscription_user" ON "subscription" ("userId")`,
    );

    /**
     * docs/11 §6: one trial per identity, "keyed on phone_hash (not device — devices are shared,
     * and device-keyed trials punish families)".
     *
     * A table of its own rather than a column on `user`: the hash is the only thing needed, it
     * outlives the account that used it (that is the point — deleting the account must not hand
     * out a second trial), and `user` is a table nobody should widen casually.
     */
    await queryRunner.query(`
      CREATE TABLE "trial_grant" (
        "phoneHash" character varying NOT NULL,
        "userId" integer,
        "tier" character varying NOT NULL,
        "grantedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_trial_grant" PRIMARY KEY ("phoneHash"),
        CONSTRAINT "FK_trial_grant_user"
          FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE SET NULL
      )
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "trial_grant"`);
    await queryRunner.query(`DROP INDEX "public"."IDX_subscription_user"`);
    await queryRunner.query(`DROP INDEX "public"."UQ_subscription_live"`);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_subscription_user" ON "subscription" ("userId")`,
    );
    await queryRunner.query(
      `ALTER TABLE "subscription" DROP CONSTRAINT "CHK_subscription_status"`,
    );
    await queryRunner.query(`
      ALTER TABLE "subscription"
        DROP COLUMN "trialEndsAt",
        DROP COLUMN "cancelledAt",
        DROP COLUMN "requiresAfa",
        DROP COLUMN "autoRenew",
        DROP COLUMN "priceKey",
        DROP COLUMN "paidPaise",
        DROP COLUMN "startsAt"
    `);
  }
}
