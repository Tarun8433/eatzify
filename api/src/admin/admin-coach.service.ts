import {
  HttpStatus,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { CoachApplicationEntity } from '../coach/entities/coach-application.entity';
import type {
  CoachApplicationStatus,
  CoachDiscipline,
} from '../coach/entities/coach-application.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { RoleEnum } from '../roles/roles.enum';
import { basename, resolve } from 'node:path';
import { AuditService } from './audit.service';
import { maskPhone } from './admin-clients.service';
import { FilesService } from '../files/files.service';

/// One row of the review queue. Deliberately NOT the applicant's name, email or phone: docs/13 §4
/// says mask PII by default in admin list views and reveal on an audited action, so the list is
/// browsable without every scroll writing an audit row. `GET /admin/users/{id}` is the audited read.
export interface ApplicationQueueRow {
  id: string;
  user_id: number;
  /// A name is not the PII docs/13 §4 asks to mask — it names the row so a reviewer can find the
  /// person they were asked about. Email and phone stay behind the audited reveal.
  name: string | null;
  /// Masked, like the client roster (docs/13 §4). The full number is on the audited reveal.
  phone_masked: string | null;
  status: CoachApplicationStatus;
  discipline: CoachDiscipline | null;
  submitted_at: string | null;
  waiting_days: number | null;
  has_id_document: boolean;
  has_qualification_document: boolean;
  agreement_version: string | null;
  verified_attributes: string[];
  reviewed_at: string | null;
  reviewed_by_user_id: number | null;
}

/**
 * Who the applicant actually is, plus everything they declared when they applied.
 *
 * Separate from [ApplicationQueueRow] on purpose. docs/13 §4 flags "full phone + email visible in
 * admin list views" as a defect and asks for "mask by default, reveal on an audited action" — so the
 * list carries ids and this carries the person, behind a call that writes a `read_pii` row.
 *
 * No reason header. docs/10 §4 requires one for reads of a HEALTH field; a partner applicant's own
 * name and the documents they chose to submit are neither health data nor somebody else's. The
 * audit row is what docs/13 asks for here, and demanding a clinical reason to read the name on an
 * application would make the reason meaningless.
 */
export interface ApplicantIdentity {
  user_id: number;
  name: string | null;
  email: string | null;
  phone: string | null;
  /// How they signed up. `phone` is the primary path in India (doc 20 §2), and on that path the
  /// `user` row carries no name or email at all — so a blank email here is a fact about the auth
  /// method, not a missing record. Shown so nobody reads "—" as data loss.
  auth_provider: string | null;
  discipline: CoachDiscipline | null;
  status: CoachApplicationStatus;
  agreement_version: string | null;
  agreement_accepted_at: string | null;
  submitted_at: string | null;
  /// Short-lived, signed download links belong here (docs/13 §4: private bucket, URLs <= 5 min).
  /// Until the file service issues them these are ids, which is why they are not rendered as links.
  id_document_file_id: string | null;
  qualification_document_file_id: string | null;
  verified_attributes: string[];
  rejection_reason: string | null;
  reviewed_at: string | null;
  reviewed_by_user_id: number | null;
}

/// Which of the two documents an application carries. A closed set, because the column names are
/// the contract — a free-string `kind` would let a typo become a 404 at review time.
export type DocumentKind = 'id' | 'qualification';

export interface ApplicantDocument {
  /// Absolute path on disk for the local driver. Never returned to the browser — the admin route
  /// streams the bytes, so there is no URL for anyone to share, replay or leak.
  absolutePath: string;
  filename: string;
}

export interface Reviewer {
  userId: number;
  role: string;
  ip?: string | null;
}

/**
 * The admin half of partner onboarding — `POST /admin/coaches/{id}/verify` (docs/09 §9).
 *
 * This is the route `CoachController` says it cannot reach. Before it existed an application could
 * reach `submitted` and stop there forever: the columns to decide one (`status`, `reviewedAt`,
 * `reviewedByUserId`, `rejectionReason`) were in the table and the CHECK constraint already allowed
 * `verified` and `rejected`, but nothing in the codebase ever wrote them.
 */
@Injectable()
export class AdminCoachService {
  constructor(
    @InjectRepository(CoachApplicationEntity)
    private readonly applications: Repository<CoachApplicationEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    private readonly files: FilesService,
    private readonly audit: AuditService,
  ) {}

  /// The queue. Defaults to `submitted`, because the only list with somebody waiting at the other
  /// end of it is the unreviewed one.
  async queue(
    status: CoachApplicationStatus = 'submitted',
    limit = 100,
  ): Promise<ApplicationQueueRow[]> {
    const rows = await this.applications.find({
      where: { status },
      // Oldest first: a review queue sorted newest-first is how the oldest application never gets
      // looked at.
      order: { submittedAt: 'ASC', createdAt: 'ASC' },
      take: Math.min(limit, 500),
    });

    // One lookup for the whole page rather than one per row.
    const userIds = rows.map((r) => r.userId);
    const [names, users] = await Promise.all([
      this.namesFor(userIds),
      this.users.find({ where: userIds.map((id) => ({ id })) }),
    ]);
    const phoneOf = new Map(users.map((u) => [u.id, u.phone ?? null]));

    return rows.map((row) => ({
      ...this.toQueueRow(row),
      name: names.get(row.userId) ?? null,
      phone_masked: maskPhone(phoneOf.get(row.userId) ?? null),
    }));
  }

  /// Names for a page of applicants, from the user row or the profile — whichever has one.
  private async namesFor(userIds: number[]): Promise<Map<number, string>> {
    if (userIds.length === 0) return new Map();

    const [users, profiles] = await Promise.all([
      this.users.find({ where: userIds.map((id) => ({ id })) }),
      this.profiles.find({ where: userIds.map((userId) => ({ userId })) }),
    ]);

    const profileName = new Map(
      profiles.map((p) => [p.userId, p.name?.trim() ?? '']),
    );
    const out = new Map<number, string>();

    for (const id of userIds) {
      const u = users.find((x) => x.id === id);
      const fromUser = [u?.firstName, u?.lastName]
        .filter(Boolean)
        .join(' ')
        .trim();
      const name = fromUser.length > 0 ? fromUser : (profileName.get(id) ?? '');
      if (name.length > 0) out.set(id, name);
    }
    return out;
  }

  /**
   * Reveal one applicant. Writes a `read_pii` audit row before returning — that is the "audited
   * action" docs/13 §4 trades the masking for, and a reveal nobody can trace is just an unmasked
   * list with extra steps.
   */
  async identity(userId: number, reader: Reviewer): Promise<ApplicantIdentity> {
    const application = await this.applications.findOne({ where: { userId } });
    if (!application) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'APPLICATION_NOT_FOUND' },
      });
    }

    const user = await this.users.findOne({ where: { id: userId } });
    const profile = await this.profiles.findOne({ where: { userId } });

    await this.audit.record({
      actorUserId: reader.userId,
      actorRole: reader.role,
      action: 'read_pii',
      resource: `coach_application/${application.id}`,
      subjectUserId: userId,
      // What was looked at, never the values themselves — rule 5 keeps PII out of logs, and this
      // table is a log.
      meta: { fields: ['name', 'email', 'phone'] },
      ip: reader.ip,
    });

    /**
     * The `user` row's name, falling back to the profile's.
     *
     * A phone-OTP signup never fills `user.firstName` — the name is asked for during onboarding and
     * lands on `profile.name`. Reading only the user row showed "No name on file" for every partner
     * who signed up the way most Indian users will, which is the majority path, not an edge case.
     */
    const fromUser = [user?.firstName, user?.lastName]
      .filter(Boolean)
      .join(' ')
      .trim();
    const name = fromUser.length > 0 ? fromUser : (profile?.name?.trim() ?? '');

    return {
      user_id: userId,
      name: name.length > 0 ? name : null,
      email: user?.email ?? null,
      phone: user?.phone ?? null,
      auth_provider: user?.provider ?? null,
      discipline: application.discipline,
      status: application.status,
      agreement_version: application.agreementVersion,
      agreement_accepted_at:
        application.agreementAcceptedAt?.toISOString() ?? null,
      submitted_at: application.submittedAt?.toISOString() ?? null,
      id_document_file_id: application.idDocumentFileId,
      qualification_document_file_id: application.qualificationDocumentFileId,
      verified_attributes: application.verifiedAttributes,
      rejection_reason: application.rejectionReason,
      reviewed_at: application.reviewedAt?.toISOString() ?? null,
      reviewed_by_user_id: application.reviewedByUserId,
    };
  }

  /**
   * Locate one of an applicant's documents for streaming, and record that it was opened.
   *
   * docs/13 §4 puts verification documents in a private bucket behind signed URLs of five minutes or
   * less. The local driver has no bucket and no signing, and the boilerplate's `GET /files/:path` is
   * UNAUTHENTICATED — anyone who guesses a filename downloads anybody's ID. So this does not hand
   * out a URL at all: the admin route streams the bytes under the reviewer's own token, which is
   * stricter than a five-minute link and cannot be forwarded. Recorded as D-184.
   *
   * The path is rebuilt from the basename rather than trusted from the database, so a poisoned
   * `file.path` row cannot walk out of the uploads directory.
   */
  async document(
    userId: number,
    kind: DocumentKind,
    reader: Reviewer,
  ): Promise<ApplicantDocument> {
    const application = await this.applications.findOne({ where: { userId } });
    if (!application) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'APPLICATION_NOT_FOUND' },
      });
    }

    const fileId =
      kind === 'id'
        ? application.idDocumentFileId
        : application.qualificationDocumentFileId;

    if (!fileId) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'DOCUMENT_NOT_ON_FILE' },
      });
    }

    const file = await this.files.findById(fileId);
    if (!file) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'DOCUMENT_MISSING' },
      });
    }

    // `file.path` is a URL path like `/api/v1/files/<name>`; only the basename is used, and
    // anything with a separator or a traversal segment in it is refused rather than resolved.
    const filename = basename(file.path);
    if (filename !== file.path.split('/').pop() || filename.includes('..')) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'DOCUMENT_MISSING' },
      });
    }

    await this.audit.record({
      actorUserId: reader.userId,
      actorRole: reader.role,
      action: 'read_pii',
      resource: `coach_application/${application.id}/document/${kind}`,
      subjectUserId: userId,
      // Which document, never its contents or its storage path.
      meta: { document: kind },
      ip: reader.ip,
    });

    return {
      absolutePath: resolve(process.cwd(), 'files', filename),
      filename,
    };
  }

  /**
   * docs/12 §6 level 2: "ID + qualification document on file", where on file means someone looked.
   *
   * `verifiedAttributes` is required and must be non-empty. Eatzify is not an accrediting body
   * (doc 00 §8) so the claim it can make is "we saw this document", never "this person is
   * qualified" — and a verification that records nothing about what was checked makes exactly the
   * claim the docs forbid.
   */
  async verify(
    userId: number,
    verifiedAttributes: string[],
    reviewer: Reviewer,
  ): Promise<ApplicationQueueRow> {
    const application = await this.requireReviewable(userId);

    if (verifiedAttributes.length === 0) {
      throw this.refusal(
        'VERIFIED_ATTRIBUTES_REQUIRED',
        'Record what was checked before verifying.',
      );
    }

    const saved = await this.applications.save({
      ...application,
      status: 'verified' as const,
      verifiedAttributes,
      reviewedAt: new Date(),
      reviewedByUserId: reviewer.userId,
      // A previous rejection's reason must not survive an approval.
      rejectionReason: null,
    });

    await this.promoteToVerifiedCoach(userId);

    await this.audit.record({
      actorUserId: reviewer.userId,
      actorRole: reviewer.role,
      action: 'coach_verify',
      resource: `coach_application/${application.id}`,
      subjectUserId: userId,
      // What was claimed against what was confirmed — the whole point of keeping both.
      meta: {
        verified_attributes: verifiedAttributes,
        declared_discipline: application.discipline,
      },
      ip: reviewer.ip,
    });

    return this.toQueueRow(saved);
  }

  /// A rejection the applicant cannot read is a dead end with no way out, so the reason is required
  /// and is shown to them (rule 7: the server authors user-facing copy, and here the reviewer does).
  async reject(
    userId: number,
    reason: string,
    reviewer: Reviewer,
  ): Promise<ApplicationQueueRow> {
    const application = await this.requireReviewable(userId);

    const trimmed = reason.trim();
    if (trimmed.length === 0) {
      throw this.refusal(
        'REJECTION_REASON_REQUIRED',
        'A rejection has to say why.',
      );
    }

    const saved = await this.applications.save({
      ...application,
      status: 'rejected' as const,
      rejectionReason: trimmed,
      reviewedAt: new Date(),
      reviewedByUserId: reviewer.userId,
    });

    // No demotion. docs/12 §6 makes the accepted agreement the whole of level 1, and a rejected
    // level 2 application does not undo an agreement the person still stands by.
    await this.audit.record({
      actorUserId: reviewer.userId,
      actorRole: reviewer.role,
      action: 'coach_reject',
      resource: `coach_application/${application.id}`,
      subjectUserId: userId,
      // The reason is the applicant's copy, not a note about them — safe to keep, and useless to
      // audit without.
      meta: { declared_discipline: application.discipline },
      ip: reviewer.ip,
    });

    return this.toQueueRow(saved);
  }

  /// Only a submitted application is reviewable. A draft has not been handed over yet, and one that
  /// is already settled needs a deliberate new decision rather than a second click on an old screen.
  private async requireReviewable(
    userId: number,
  ): Promise<CoachApplicationEntity> {
    const application = await this.applications.findOne({ where: { userId } });

    if (!application) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'APPLICATION_NOT_FOUND' },
      });
    }

    if (application.status !== 'submitted') {
      throw this.refusal(
        'APPLICATION_NOT_SUBMITTED',
        `This application is ${application.status}, not awaiting review.`,
      );
    }

    return application;
  }

  /// Level 2 is `coach_l2` (docs/10 §1). Never downward, and never past `coach_l3` — a coach who has
  /// already been raised to an active coaching relationship must not be knocked back by a
  /// verification landing late.
  private async promoteToVerifiedCoach(userId: number): Promise<void> {
    const user = await this.users.findOne({ where: { id: userId } });
    if (!user) return;

    const current = user.role?.id ?? RoleEnum.user;
    if (current >= RoleEnum.coach_l2) return;

    await this.users.update(userId, { role: { id: RoleEnum.coach_l2 } });
  }

  private toQueueRow(row: CoachApplicationEntity): ApplicationQueueRow {
    return {
      id: row.id,
      user_id: row.userId,
      name: null,
      phone_masked: null,
      status: row.status,
      discipline: row.discipline,
      submitted_at: row.submittedAt?.toISOString() ?? null,
      waiting_days: this.daysSince(row.submittedAt),
      // Booleans in the list, ids only on the audited detail read: docs/13 §4 keeps verification
      // documents in a private bucket behind short-lived signed URLs, never handed out in a list.
      has_id_document: row.idDocumentFileId !== null,
      has_qualification_document: row.qualificationDocumentFileId !== null,
      agreement_version: row.agreementVersion,
      verified_attributes: row.verifiedAttributes,
      reviewed_at: row.reviewedAt?.toISOString() ?? null,
      reviewed_by_user_id: row.reviewedByUserId,
    };
  }

  private daysSince(date: Date | null): number | null {
    if (!date) return null;
    return Math.max(
      0,
      Math.floor((Date.now() - new Date(date).getTime()) / 86_400_000),
    );
  }

  private refusal(code: string, userMessage: string): Error {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: userMessage },
    });
  }
}
