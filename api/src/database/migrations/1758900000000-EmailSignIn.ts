import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * D-250: email and password become the only way in; the phone number is contact information.
 *
 * - `email_otp` holds the 6-digit code that proves someone owns the address they signed up with.
 *   Only a SHA-256 of the code is stored, so a database read does not hand anyone a live code.
 * - `user.phone` stops being unique. It identified an account while phone OTP was the login; now
 *   two people may share a number (a family phone), and a number left on an old phone-login
 *   account must not block that person signing up with their email.
 */
export class EmailSignIn1758900000000 implements MigrationInterface {
  name = 'EmailSignIn1758900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "email_otp" (
        "id" SERIAL NOT NULL,
        "userId" integer NOT NULL,
        "codeHash" character varying(64) NOT NULL,
        "expiresAt" TIMESTAMP WITH TIME ZONE NOT NULL,
        "attempts" integer NOT NULL DEFAULT 0,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_email_otp_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_email_otp_user" FOREIGN KEY ("userId")
          REFERENCES "user"("id") ON DELETE CASCADE,
        CONSTRAINT "CHK_email_otp_attempts" CHECK ("attempts" >= 0)
      )
    `);
    await queryRunner.query(
      `CREATE INDEX "IDX_email_otp_user_created" ON "email_otp" ("userId", "createdAt")`,
    );
    await queryRunner.query(
      `ALTER TABLE "user" DROP CONSTRAINT IF EXISTS "UQ_user_phone"`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // Restoring uniqueness fails if two accounts now share a number — which is the point of
    // having dropped it. Forward-only in practice (api/CLAUDE.md rule 8).
    await queryRunner.query(
      `ALTER TABLE "user" ADD CONSTRAINT "UQ_user_phone" UNIQUE ("phone")`,
    );
    await queryRunner.query(`DROP INDEX "public"."IDX_email_otp_user_created"`);
    await queryRunner.query(`DROP TABLE "email_otp"`);
  }
}
