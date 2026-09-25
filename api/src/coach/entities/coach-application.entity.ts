import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  OneToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';

/// docs/12 §6. One row per applicant, because a person is either a partner or applying to be one —
/// a history of attempts belongs in the audit log, not in a table the coach surface has to read.
export const COACH_APPLICATION_STATUS = [
  /// Agreement accepted, documents not yet complete. Already a level 1 affiliate.
  'draft',
  /// Documents in, waiting for a human. docs/12 §6 level 2 is "ID + qualification document on
  /// file", and "on file" means someone looked.
  'submitted',
  'verified',
  'rejected',
] as const;

export type CoachApplicationStatus = (typeof COACH_APPLICATION_STATUS)[number];

/// What the applicant SAYS they are. Mirrors `Profession` in the Flutter app minus `none` — a
/// person with no profession is not applying — plus `other`, because a closed list with no escape
/// hatch gets answered wrongly rather than not at all.
///
/// Self-declared and never treated as more than that: `verifiedAttributes` is what a human actually
/// confirmed, and the two are separate columns precisely so the gap between them stays visible.
export const COACH_DISCIPLINES = [
  'trainer',
  'nutritionist',
  'doctor',
  'other',
] as const;

export type CoachDiscipline = (typeof COACH_DISCIPLINES)[number];

@Entity({ name: 'coach_application' })
export class CoachApplicationEntity extends BaseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @OneToOne(() => UserEntity)
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column({ unique: true })
  userId: number;

  @Column({ type: 'varchar', default: 'draft' })
  status: CoachApplicationStatus;

  /// Self-declared, nullable because every row written before this column existed has no answer and
  /// inventing one would be worse than saying so. Lives HERE and not on the profile: docs/13 §4 says
  /// collect less, and the Flutter `Profession` enum's own comment says the record that matters is
  /// the application. A DB CHECK holds it to [COACH_DISCIPLINES] — free text would make the count
  /// this exists to answer unanswerable.
  @Column({ type: 'varchar', nullable: true })
  discipline: CoachDiscipline | null;

  /// When the partner agreement was accepted, and which version of it.
  ///
  /// docs/12 §6 makes the agreement the whole of level 1 — no verification, no documents — so this
  /// timestamp is what a level 1 affiliate's standing rests on. The version matters because the
  /// agreement will change and "they agreed" is only evidence if it says to what.
  @Column({ type: 'timestamptz', nullable: true })
  agreementAcceptedAt: Date | null;

  @Column({ type: 'varchar', nullable: true })
  agreementVersion: string | null;

  /// docs/12 §6's SECOND agreement — the coaching one, which is what level 3 rests on alongside a
  /// client grant (D-235). Separate from the partner agreement above because it is a different
  /// promise: that one is about referrals and commission, this one is about being responsible for
  /// another person's diet. Versioned for the same reason the first one is.
  @Column({ type: 'timestamptz', nullable: true })
  coachingAgreementAcceptedAt: Date | null;

  @Column({ type: 'varchar', nullable: true })
  coachingAgreementVersion: string | null;

  /// Uploaded through `POST /files/upload`, referenced by id. Level 2 needs both (docs/12 §6).
  @Column({ type: 'uuid', nullable: true })
  idDocumentFileId: string | null;

  @Column({ type: 'uuid', nullable: true })
  qualificationDocumentFileId: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  submittedAt: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  reviewedAt: Date | null;

  /// The admin who decided. A verification nobody is accountable for is not a verification.
  @Column({ type: 'int', nullable: true })
  reviewedByUserId: number | null;

  /// **What was actually checked** — docs/02 FR-8.3 asks for an explicit "what we verified" record,
  /// and docs/12 §6 requires publishing exactly what verification means. Eatzify is not an
  /// accrediting body (doc 00 §8), so the claim it can make is "we saw this document", never "this
  /// person is qualified". This column is that distinction, stored.
  @Column({ type: 'jsonb', default: () => "'[]'" })
  verifiedAttributes: string[];

  /// Shown to the applicant. Server-authored, like every other user-facing string (rule 7).
  @Column({ type: 'text', nullable: true })
  rejectionReason: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
