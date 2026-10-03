import { Entity, PrimaryColumn } from 'typeorm';

/// Admin panel plan, Phase D: a day this person used the app (Indian calendar day).
@Entity({ name: 'user_activity_day' })
export class UserActivityDayEntity {
  @PrimaryColumn()
  userId: number;

  /// `YYYY-MM-DD`.
  @PrimaryColumn({ type: 'date' })
  day: string;
}
