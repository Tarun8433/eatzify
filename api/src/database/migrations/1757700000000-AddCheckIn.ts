import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/02 FR-5.2 and docs/09 §6. The coach's weekly review of one client.
 *
 * One row per coach per client per week, and the week is a DIARY date (the Monday) rather than an
 * instant — api/CLAUDE.md rule 4 keeps the 04:00 IST boundary in one place, and a check-in that
 * fell due at a different hour for each coach would be a second opinion about when a day is.
 *
 * The unique index is what makes the lazy generation safe: the queue creates this week's row when
 * it is first read, and two tabs opening at once must not create two.
 */
export class AddCheckIn1757700000000 implements MigrationInterface {
  name = 'AddCheckIn1757700000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "check_in" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "coachUserId" integer NOT NULL,
        "clientUserId" integer NOT NULL,
        "dueOn" date NOT NULL,
        "status" character varying NOT NULL DEFAULT 'due',
        "completedAt" TIMESTAMP WITH TIME ZONE,
        "notes" text,
        "actions" jsonb,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_check_in" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_check_in_status"
          CHECK ("status" IN ('due', 'completed', 'missed')),
        CONSTRAINT "UQ_check_in_week" UNIQUE ("coachUserId", "clientUserId", "dueOn"),
        CONSTRAINT "FK_check_in_coach"
          FOREIGN KEY ("coachUserId") REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_check_in_client"
          FOREIGN KEY ("clientUserId") REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_check_in_coach_status" ON "check_in" ("coachUserId", "status")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_check_in_coach_status"`);
    await queryRunner.query(`DROP TABLE "check_in"`);
  }
}
