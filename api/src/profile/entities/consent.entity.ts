import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';

/// FR-1.7 / docs/13. Itemised consent, append-only: a withdrawal is a new row, never a delete, so
/// "what was this user consenting to when we stored that health field?" stays answerable.
@Entity({ name: 'consent' })
export class ConsentEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  type: string;

  @Column({ type: 'boolean' })
  granted: boolean;

  @Column({ type: 'varchar', default: '1.0.0' })
  policyVersion: string;

  @CreateDateColumn()
  grantedAt: Date;
}
