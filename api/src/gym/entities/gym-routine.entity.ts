import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';
import type { RoutineExercise } from '../gym-types';

@Entity({ name: 'gym_routine' })
export class GymRoutineEntity {
  @PrimaryGeneratedColumn()
  id: number;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'userId' })
  user: UserEntity;

  @Index()
  @Column()
  userId: number;

  @Column({ type: 'varchar' })
  name: string;

  @Column({ type: 'varchar', default: 'strength' })
  icon: string;

  /// The routine-wide rule; an exercise may override it.
  @Column({ type: 'varchar', default: 'linear' })
  progression: string;

  /// Edited and saved whole, in order. Adjacent entries sharing `superset` are one superset.
  @Column({ type: 'jsonb', default: () => "'[]'" })
  exercises: RoutineExercise[];

  @Column({ type: 'integer', default: 0 })
  position: number;

  @Column({ type: 'boolean', default: false })
  isDemo: boolean;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;
}
