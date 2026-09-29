import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/// One emailed sign-up code (D-250). Only its SHA-256 is kept: reading this table never yields a
/// live code. Rows stay after use-by so the per-hour send limit can count them.
@Entity({ name: 'email_otp' })
@Index('IDX_email_otp_user_created', ['userId', 'createdAt'])
export class EmailOtpEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ type: 'integer' })
  userId: number;

  @Column({ type: 'varchar', length: 64 })
  codeHash: string;

  @Column({ type: 'timestamptz' })
  expiresAt: Date;

  @Column({ type: 'integer', default: 0 })
  attempts: number;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}
