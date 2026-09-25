import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { MealPhotoSweep } from './meal-photo.sweep';

/// 04:30 IST: quiet, after the 04:00 diary boundary, and clear of the subscription sweep at 03:30.
export const MEAL_PHOTO_SWEEP_CRON = '30 4 * * *';

/// The clock, and nothing else — the work is [MealPhotoSweep].
@Injectable()
export class MealPhotoScheduler {
  private readonly log = new Logger(MealPhotoScheduler.name);

  constructor(private readonly sweep: MealPhotoSweep) {}

  @Cron(MEAL_PHOTO_SWEEP_CRON, {
    name: 'meal-photo-sweep',
    timeZone: 'Asia/Kolkata',
  })
  async daily(): Promise<void> {
    const removed = await this.sweep.run(new Date());
    // A count only: no user, no entry, nothing about anybody's meal (api rule 5).
    this.log.log(`meal photo sweep: ${removed} removed`);
  }
}
