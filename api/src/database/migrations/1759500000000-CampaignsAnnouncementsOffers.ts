import { MigrationInterface, QueryRunner } from 'typeorm';

/// Admin panel plan, Phase C.
///
/// - `notification_campaign`: a message sent (or scheduled) to an audience over one or more
///   channels, with what happened on each channel. The audience spec is kept, not the list of
///   people, so the row carries no personal data.
/// - `device_token`: where a push notification goes. One row per app install, removed when the
///   app signs out or the push service says the token is dead.
/// - `announcement`: in-app news and "important update" banners.
/// - `coupon` gains what an offer card needs: words, a banner, a start and who may use it.
export class CampaignsAnnouncementsOffers1759500000000 implements MigrationInterface {
  name = 'CampaignsAnnouncementsOffers1759500000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "notification_campaign" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "title" character varying(120) NOT NULL,
        "body" character varying(1000) NOT NULL,
        "contentClass" character varying NOT NULL,
        "segment" jsonb NOT NULL DEFAULT '{}',
        "channels" text[] NOT NULL,
        "status" character varying NOT NULL DEFAULT 'scheduled',
        "scheduledAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "sentAt" TIMESTAMP WITH TIME ZONE,
        "audience" integer,
        "results" jsonb NOT NULL DEFAULT '{}',
        "error" character varying(500),
        "createdBy" integer NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_notification_campaign" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_campaign_status" CHECK ("status" IN ('scheduled', 'sending', 'sent', 'failed', 'cancelled')),
        CONSTRAINT "CHK_campaign_class" CHECK ("contentClass" IN ('clinical', 'service', 'commercial'))
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_campaign_due" ON "notification_campaign" ("status", "scheduledAt")`,
    );

    await q.query(`
      CREATE TABLE "device_token" (
        "id" SERIAL NOT NULL,
        "userId" integer NOT NULL,
        "token" character varying(512) NOT NULL,
        "platform" character varying NOT NULL,
        "lastSeenAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_device_token" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_device_token" UNIQUE ("token"),
        CONSTRAINT "FK_device_token_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "CHK_device_platform" CHECK ("platform" IN ('android', 'ios'))
      )
    `);
    await q.query(
      `CREATE INDEX "IDX_device_token_user" ON "device_token" ("userId")`,
    );

    await q.query(`
      CREATE TABLE "announcement" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "title" character varying(120) NOT NULL,
        "body" character varying(2000) NOT NULL,
        "imageUrl" character varying(500),
        "priority" character varying NOT NULL DEFAULT 'normal',
        "audience" character varying NOT NULL DEFAULT 'all',
        "status" character varying NOT NULL DEFAULT 'draft',
        "startsAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "endsAt" TIMESTAMP WITH TIME ZONE,
        "createdBy" integer NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_announcement" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_announcement_priority" CHECK ("priority" IN ('normal', 'important', 'critical')),
        CONSTRAINT "CHK_announcement_audience" CHECK ("audience" IN ('all', 'free', 'paid')),
        CONSTRAINT "CHK_announcement_status" CHECK ("status" IN ('draft', 'published', 'archived')),
        CONSTRAINT "CHK_announcement_window" CHECK ("endsAt" IS NULL OR "endsAt" > "startsAt")
      )
    `);

    await q.query(`ALTER TABLE "coupon" ADD "title" character varying(80)`);
    await q.query(
      `ALTER TABLE "coupon" ADD "description" character varying(300)`,
    );
    await q.query(
      `ALTER TABLE "coupon" ADD "bannerUrl" character varying(500)`,
    );
    await q.query(
      `ALTER TABLE "coupon" ADD "startsAt" TIMESTAMP WITH TIME ZONE`,
    );
    await q.query(
      `ALTER TABLE "coupon" ADD "eligibility" character varying NOT NULL DEFAULT 'all'`,
    );
    await q.query(`ALTER TABLE "coupon" ADD "tier" character varying`);
    await q.query(`
      ALTER TABLE "coupon" ADD CONSTRAINT "CHK_coupon_eligibility"
        CHECK ("eligibility" IN ('all', 'new_users'))
    `);
    await q.query(`
      ALTER TABLE "coupon" ADD CONSTRAINT "CHK_coupon_tier"
        CHECK ("tier" IS NULL OR "tier" IN ('BASIC', 'PRO'))
    `);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`ALTER TABLE "coupon" DROP CONSTRAINT "CHK_coupon_tier"`);
    await q.query(
      `ALTER TABLE "coupon" DROP CONSTRAINT "CHK_coupon_eligibility"`,
    );
    for (const c of [
      'tier',
      'eligibility',
      'startsAt',
      'bannerUrl',
      'description',
      'title',
    ]) {
      await q.query(`ALTER TABLE "coupon" DROP COLUMN "${c}"`);
    }
    await q.query(`DROP TABLE "announcement"`);
    await q.query(`DROP TABLE "device_token"`);
    await q.query(`DROP TABLE "notification_campaign"`);
  }
}
