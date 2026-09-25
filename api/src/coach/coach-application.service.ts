import {
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { MoreThan, Repository } from 'typeorm';
import { CoachApplicationEntity } from './entities/coach-application.entity';
import { CoachGrantEntity } from './entities/coach-grant.entity';
import type { CoachDiscipline } from './entities/coach-application.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { RoleEnum } from '../roles/roles.enum';
import {
  ALREADY_SUBMITTED,
  ALREADY_VERIFIED,
  AGREEMENT_REQUIRED,
  COACHING_NEEDS_VERIFICATION,
  DOCUMENTS_REQUIRED,
  WHAT_VERIFICATION_MEANS,
} from './coach-copy';

export type CoachApplicationView = {
  status: string;
  level: number;
  /// What the applicant SAYS they do. Null until they have answered, and null is shown as a
  /// question rather than guessed at — onboarding's answer to the same question is routing only
  /// and is deliberately never stored (see `Profession` in the app).
  discipline: CoachDiscipline | null;
  agreement_accepted: boolean;
  agreement_version: string | null;
  /// docs/12 §6's second agreement, which level 3 rests on (D-235).
  coaching_agreement_accepted: boolean;
  coaching_agreement_version: string | null;
  has_id_document: boolean;
  has_qualification_document: boolean;
  submitted_at: string | null;
  verified_attributes: string[];
  rejection_reason: string | null;
  /// docs/12 §6 requires this to be publishable wherever the badge is. Sent with the application
  /// so no client has to author it.
  what_verification_means: string;
};

/**
 * Coach onboarding, docs/12 §6.
 *
 * Two levels, and the difference between them is the whole design:
 *
 * - **Level 1 (Affiliate)** is "signup + agreement". No documents, no review. Accepting the
 *   agreement IS the qualification, so the role is granted immediately.
 * - **Level 2 (Verified)** is "ID + qualification document on file", and "on file" means a human
 *   looked. This service can take an application to `submitted` and no further — only an admin
 *   moves it to `verified`, which is `POST /admin/coaches/{id}/verify` (docs/09 §9) and is E8.
 *
 * - **Level 3 (Coaching)** is "level 2 + active coaching agreement + client grant" (D-235). The
 *   partner can supply the first two; only a CLIENT can supply the third. So the promotion runs
 *   from both ends — when the coaching agreement is accepted, and when a client accepts an invite —
 *   and happens on whichever completes the set. Neither end can grant it alone.
 */
@Injectable()
export class CoachApplicationService {
  constructor(
    @InjectRepository(CoachApplicationEntity)
    private readonly applications: Repository<CoachApplicationEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(CoachGrantEntity)
    private readonly grants: Repository<CoachGrantEntity>,
  ) {}

  async current(userId: number): Promise<CoachApplicationView | null> {
    const row = await this.applications.findOne({ where: { userId } });
    if (!row) return null;

    // Level 3 is a fact about the ROLE, not the application row — a client's grant made it, and
    // the row cannot see grants. So it is read back from the user rather than recomputed here.
    const user = await this.users.findOne({ where: { id: userId } });
    return this.toView(row, user?.role?.id === RoleEnum.coach_l3);
  }

  /**
   * docs/12 §6's coaching agreement — the partner's half of level 3.
   *
   * Only for a verified partner: the agreement is a promise about coaching somebody, and an
   * unverified one has not had their qualification looked at yet. Idempotent like the first
   * agreement, for the same reason — a second tap on a slow connection must change nothing.
   */
  async acceptCoachingAgreement(
    userId: number,
    version: string,
    now = new Date(),
  ): Promise<CoachApplicationView> {
    const existing = await this.applications.findOne({ where: { userId } });

    if (!existing || existing.status !== 'verified') {
      throw this.refusal('VERIFICATION_REQUIRED', COACHING_NEEDS_VERIFICATION);
    }

    if (!existing.coachingAgreementAcceptedAt) {
      existing.coachingAgreementAcceptedAt = now;
      existing.coachingAgreementVersion = version;
      await this.applications.save(existing);
    }

    await this.promoteToCoachingIfEligible(userId, now);
    return (await this.current(userId))!;
  }

  /**
   * Level 3, when — and only when — all three of docs/12 §6's conditions hold: verified (level 2),
   * the coaching agreement accepted, and at least one client's grant active right now.
   *
   * Called from both ends. A partner who accepts the agreement after their first client said yes is
   * promoted then; one who accepted first is promoted the moment a client says yes. Promotion only —
   * a coach whose last grant lapses keeps the level, because demotion is an admin decision with a
   * reason attached (D-169), not a side effect of a client's subscription ending.
   */
  async promoteToCoachingIfEligible(
    coachUserId: number,
    now = new Date(),
  ): Promise<boolean> {
    const user = await this.users.findOne({ where: { id: coachUserId } });
    if (user?.role?.id !== RoleEnum.coach_l2) return false;

    const application = await this.applications.findOne({
      where: { userId: coachUserId },
    });
    if (!application?.coachingAgreementAcceptedAt) return false;

    const activeGrant = await this.grants.findOne({
      where: { coachUserId, status: 'active', expiresAt: MoreThan(now) },
    });
    if (!activeGrant) return false;

    await this.promoteTo(coachUserId, RoleEnum.coach_l3);
    return true;
  }

  /**
   * What the applicant says they do.
   *
   * Writable before the agreement, unlike every other step: it is the first question the partner
   * screen asks, and refusing it until the agreement is accepted would mean asking someone to
   * agree to a partnership before saying what kind of partner they are.
   *
   * Changeable for exactly as long as nobody is reviewing it. Once an application is submitted the
   * discipline is part of what a human is checking the documents AGAINST — a qualification
   * certificate means something different for a doctor than for a trainer — so switching it
   * underneath them would invalidate the review in progress without the reviewer knowing.
   */
  async setDiscipline(
    userId: number,
    discipline: CoachDiscipline,
  ): Promise<CoachApplicationView> {
    const existing = await this.applications.findOne({ where: { userId } });
    if (existing) this.refuseIfSettled(existing);

    const saved = await this.applications.save({
      ...(existing ?? {}),
      userId,
      status: existing?.status ?? 'draft',
      discipline,
    });

    return this.toView(saved as CoachApplicationEntity);
  }

  /**
   * Accept the partner agreement. This is the whole of level 1.
   *
   * Idempotent: accepting twice re-records nothing and does not reset a submitted application.
   * A partner who taps again on a slow connection must not fall back down a level.
   */
  async acceptAgreement(
    userId: number,
    version: string,
    discipline?: CoachDiscipline,
  ): Promise<CoachApplicationView> {
    const existing = await this.applications.findOne({ where: { userId } });

    if (existing?.agreementAcceptedAt) return this.toView(existing);

    const saved = await this.applications.save({
      ...(existing ?? {}),
      userId,
      status: existing?.status ?? 'draft',
      agreementAcceptedAt: new Date(),
      agreementVersion: version,
      // Captured at the moment the application starts, because that is the only point the applicant
      // is asked. `?? null` rather than leaving it undefined: an applicant who skipped the question
      // has NOT declared nothing by accident, and the admin count says "unknown" rather than
      // guessing a discipline for them.
      discipline: discipline ?? existing?.discipline ?? null,
    });

    // docs/12 §6: level 1 unlocks on agreement alone. Only ever a PROMOTION — a user who is
    // already a verified coach does not drop to affiliate by re-accepting.
    await this.promoteTo(userId, RoleEnum.coach_l1);

    return this.toView(saved as CoachApplicationEntity);
  }

  /**
   * Attach uploaded documents. Ids only: the files live in the files module, and a row that
   * carried the bytes would put identity documents in every query that reads an application.
   */
  async attachDocuments(
    userId: number,
    documents: {
      idDocumentFileId?: string;
      qualificationDocumentFileId?: string;
    },
  ): Promise<CoachApplicationView> {
    const existing = await this.requireApplication(userId);
    this.refuseIfSettled(existing);

    const saved = await this.applications.save({
      ...existing,
      idDocumentFileId: documents.idDocumentFileId ?? existing.idDocumentFileId,
      qualificationDocumentFileId:
        documents.qualificationDocumentFileId ??
        existing.qualificationDocumentFileId,
    });

    return this.toView(saved);
  }

  /**
   * Hand the application to a human. The last thing this service can do.
   *
   * Both documents are required, because docs/12 §6's level 2 is exactly "ID + qualification
   * document on file" — submitting with one of them is asking a reviewer to verify something that
   * is not there.
   */
  async submit(userId: number): Promise<CoachApplicationView> {
    const existing = await this.requireApplication(userId);
    this.refuseIfSettled(existing);

    if (!existing.idDocumentFileId || !existing.qualificationDocumentFileId) {
      throw this.refusal('DOCUMENTS_REQUIRED', DOCUMENTS_REQUIRED);
    }

    const saved = await this.applications.save({
      ...existing,
      status: 'submitted' as const,
      submittedAt: new Date(),
    });

    return this.toView(saved);
  }

  private async requireApplication(
    userId: number,
  ): Promise<CoachApplicationEntity> {
    const existing = await this.applications.findOne({ where: { userId } });
    if (existing?.agreementAcceptedAt) return existing;

    // The agreement is the first step and every later one depends on it being on record.
    throw this.refusal('AGREEMENT_REQUIRED', AGREEMENT_REQUIRED);
  }

  /// An application a human has already decided on, or is deciding on, is not the applicant's to
  /// edit. Otherwise a reviewer can approve one set of documents while another is being swapped in.
  private refuseIfSettled(application: CoachApplicationEntity): void {
    if (application.status === 'submitted') {
      throw this.refusal('APPLICATION_IN_REVIEW', ALREADY_SUBMITTED);
    }
    if (application.status === 'verified') {
      throw this.refusal('ALREADY_VERIFIED', ALREADY_VERIFIED);
    }
  }

  /// Never a demotion. Levels only ever go up through this path; coming back down is an admin
  /// decision with a reason attached, not a side effect of tapping a button twice.
  private async promoteTo(userId: number, role: RoleEnum): Promise<void> {
    const user = await this.users.findOne({ where: { id: userId } });
    if (!user) return;

    const current = user.role?.id ?? RoleEnum.user;
    const isCoach =
      current === RoleEnum.coach_l1 ||
      current === RoleEnum.coach_l2 ||
      current === RoleEnum.coach_l3;

    if (isCoach && current >= role) return;

    await this.users.update(userId, { role: { id: role } });
  }

  private refusal(code: string, userMessage: string): Error {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: userMessage },
    });
  }

  private toView(
    row: CoachApplicationEntity,
    isCoaching = false,
  ): CoachApplicationView {
    return {
      status: row.status,
      discipline: row.discipline ?? null,
      // Level 2 is only real once a human has said so; until then an accepted agreement is a
      // level 1 affiliate, whatever documents are sitting on the row.
      level: isCoaching ? 3 : row.status === 'verified' ? 2 : 1,
      // `Boolean`, not `!== null`. A row this service has just created has never been near the
      // database, so a column nobody set is UNDEFINED rather than null — and `undefined !== null`
      // is true, which reported an untouched application as having accepted the agreement.
      agreement_accepted: Boolean(row.agreementAcceptedAt),
      agreement_version: row.agreementVersion ?? null,
      coaching_agreement_accepted: Boolean(row.coachingAgreementAcceptedAt),
      coaching_agreement_version: row.coachingAgreementVersion ?? null,
      // Booleans, not ids. Whether a document exists is the applicant's business; the file itself
      // is the reviewer's, and an id in a response is an id in a log.
      has_id_document: Boolean(row.idDocumentFileId),
      has_qualification_document: Boolean(row.qualificationDocumentFileId),
      submitted_at: row.submittedAt?.toISOString() ?? null,
      verified_attributes: row.verifiedAttributes ?? [],
      rejection_reason: row.rejectionReason ?? null,
      what_verification_means: WHAT_VERIFICATION_MEANS,
    };
  }
}
