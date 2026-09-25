import {
  BaseEntity,
  Column,
  CreateDateColumn,
  Entity,
  PrimaryColumn,
} from 'typeorm';

/**
 * One admin's authenticator app.
 *
 * The secret is stored as the app needs it — a TOTP secret cannot be hashed, because the server has
 * to recompute the same code the phone did. docs/13 §7's encryption-at-rest requirement is what
 * protects this column; the application's own job is to never log it and never return it again
 * after enrolment.
 *
 * Its own table rather than columns on `user`: it is read on a handful of admin requests and never
 * on the auth path, and an admin's second factor is not part of every user row.
 */
@Entity({ name: 'admin_totp' })
export class AdminTotpEntity extends BaseEntity {
  @PrimaryColumn()
  userId: number;

  /// Base32, as every authenticator app expects it.
  @Column({ type: 'varchar' })
  secret: string;

  /// Null until the person has proved the app is set up by typing a code back.
  @Column({ type: 'timestamptz', nullable: true })
  confirmedAt: Date | null;

  /// The last code accepted, so the same one cannot be replayed inside its own 90-second window.
  @Column({ type: 'varchar', nullable: true })
  lastCode: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  lastUsedAt: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
