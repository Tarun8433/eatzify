import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';

/// One row per field changed, append-only. docs/13 wants an answer to "what did this user's record
/// say on the day that plan was generated", and `profile` is overwritten in place — so without this
/// every previous value was simply gone.
///
/// Per FIELD rather than per request: "the user changed their name 20 times" is the question being
/// asked, and a JSON blob per save makes that a scan-and-parse instead of a WHERE clause.
@Entity({ name: 'profile_change' })
@Index(['userId', 'changedAt'])
@Index(['userId', 'field'])
export class ProfileChangeEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Column()
  userId: number;

  /// Which record it came from: 'profile' or 'health_profile'.
  @Column({ type: 'varchar' })
  entity: string;

  /// The wire name, e.g. `meal_count` — the same vocabulary the API speaks, so an admin reading
  /// this does not need a mapping table to the column names.
  @Column({ type: 'varchar' })
  field: string;

  /// Stored as text whatever the column's type: an audit row is read, not computed with, and one
  /// text column keeps arrays and booleans in the same shape as everything else.
  @Column({ type: 'text', nullable: true })
  oldValue: string | null;

  @Column({ type: 'text', nullable: true })
  newValue: string | null;

  /// Who made the change. The user themselves today; a coach or admin acting on their behalf is
  /// the reason this is not assumed to equal `userId`.
  @Column()
  changedByUserId: number;

  /// Which endpoint did it, e.g. `PATCH /profile`. Cheap to store and the first thing you want
  /// when a value changed and nobody remembers doing it.
  @Column({ type: 'varchar' })
  source: string;

  @CreateDateColumn({ type: 'timestamptz' })
  changedAt: Date;
}
