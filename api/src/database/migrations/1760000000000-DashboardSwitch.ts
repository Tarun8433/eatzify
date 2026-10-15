import { MigrationInterface, QueryRunner } from 'typeorm';

/// D-269: who may switch between "My tracking" and "My clients". An app-wide setting the admin
/// edits, and a per-person override. New tables only (expand); the `user` table is untouched.
export class DashboardSwitch1760000000000 implements MigrationInterface {
  name = 'DashboardSwitch1760000000000';

  public async up(q: QueryRunner): Promise<void> {
    await q.query(`
      CREATE TABLE "app_setting" (
        "key" character varying(100) NOT NULL,
        "value" jsonb NOT NULL,
        "updatedByUserId" integer,
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_app_setting" PRIMARY KEY ("key"),
        CONSTRAINT "CHK_app_setting_dashboard_switch_audience" CHECK (
          "key" <> 'dashboard_switch.audience' OR "value" IN ('"verified"'::jsonb, '"agreement"'::jsonb)
        )
      )
    `);
    await q.query(
      `INSERT INTO "app_setting" ("key", "value") VALUES ('dashboard_switch.audience', '"verified"')`,
    );
    await q.query(`
      CREATE TABLE "dashboard_switch_override" (
        "userId" integer NOT NULL,
        "allowed" boolean NOT NULL,
        "updatedByUserId" integer NOT NULL,
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_dashboard_switch_override" PRIMARY KEY ("userId"),
        CONSTRAINT "FK_dashboard_switch_override_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
  }

  public async down(q: QueryRunner): Promise<void> {
    await q.query(`DROP TABLE "dashboard_switch_override"`);
    await q.query(`DROP TABLE "app_setting"`);
  }
}
