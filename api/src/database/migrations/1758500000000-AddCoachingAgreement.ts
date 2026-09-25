import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/12 §6: level 3 is "level 2 + active coaching agreement + client grant" (D-235).
 *
 * The coaching agreement is a second, separate promise from the partner agreement — that one is
 * about referrals and commission, this one about being responsible for another person's diet — so
 * it gets its own two columns rather than a flag on the first. Nullable: every existing partner has
 * simply not accepted it yet, which is true.
 */
export class AddCoachingAgreement1758500000000 implements MigrationInterface {
  name = 'AddCoachingAgreement1758500000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "coach_application"
        ADD COLUMN "coachingAgreementAcceptedAt" TIMESTAMP WITH TIME ZONE,
        ADD COLUMN "coachingAgreementVersion" character varying
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "coach_application"
        DROP COLUMN "coachingAgreementVersion",
        DROP COLUMN "coachingAgreementAcceptedAt"
    `);
  }
}
