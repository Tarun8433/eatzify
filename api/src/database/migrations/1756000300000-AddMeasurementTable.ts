import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddMeasurementTable1756000300000 implements MigrationInterface {
  name = 'AddMeasurementTable1756000300000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "measurement" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "kind" character varying NOT NULL,
        "value" numeric(7,2) NOT NULL,
        "unit" character varying NOT NULL,
        "diaryDate" date NOT NULL,
        "source" character varying NOT NULL DEFAULT 'manual',
        "isSuspect" boolean NOT NULL DEFAULT false,
        "recordedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_measurement" PRIMARY KEY ("id"),
        CONSTRAINT "FK_measurement_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);
    // docs/08: this constraint is load-bearing — one reading per kind per diary day is half of
    // what prevents the old build's "-30.0 kg change" readout.
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_measurement_user_kind_date" ON "measurement" ("userId", "kind", "diaryDate")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX "public"."IDX_measurement_user_kind_date"`,
    );
    await queryRunner.query(`DROP TABLE "measurement"`);
  }
}
