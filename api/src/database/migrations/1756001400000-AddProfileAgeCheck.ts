import { MigrationInterface, QueryRunner } from 'typeorm';

/// The under-18 floor, at the database (CLAUDE.md rule 10: "Onboarding rejects users under 18.
/// There is a DB CHECK constraint too. Do not add a bypass.").
///
/// The rule has always said "too", and only the service half existed — and until this session not
/// even that: onboarding STORED a minor and returned a gate, which docs/02 FR-1.2 forbids in the
/// same sentence as the 422. A constraint is what makes the floor survive the next code path that
/// forgets to ask: a seed, a repair script, an admin screen, a future importer.
///
/// `NOT VALID` deliberately. The check binds every INSERT and UPDATE from now on, but does not
/// re-scan rows already there. A deploy that fails because a minor was onboarded before the fix
/// leaves the fix un-deployed, which is the worse outcome. Validate it once the table is known
/// clean:
///
///   SELECT id FROM profile WHERE "ageYears" < 18;                    -- expect zero rows
///   ALTER TABLE profile VALIDATE CONSTRAINT "CHK_profile_age_adult"; -- then this
export class AddProfileAgeCheck1756001400000 implements MigrationInterface {
  name = 'AddProfileAgeCheck1756001400000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "profile" ADD CONSTRAINT "CHK_profile_age_adult" CHECK ("ageYears" >= 18) NOT VALID`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "profile" DROP CONSTRAINT "CHK_profile_age_adult"`,
    );
  }
}
