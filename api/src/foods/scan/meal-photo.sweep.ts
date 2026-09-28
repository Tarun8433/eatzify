import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, LessThan, Not, Repository } from 'typeorm';
import { FoodLogEntity } from '../../logs/entities/food-log.entity';
import { deleteMealPhoto, listMealPhotos } from '../../logs/meal-photo';
import { FoodScanEntity } from './food-scan.entity';

const DAY_MS = 24 * 60 * 60 * 1000;

/// docs/13 §4/§6: meal photos are kept for the shortest useful time. Configurable, not constant —
/// retention is a policy the privacy review may change.
const retentionDays = (): number =>
  Number(process.env.MEAL_PHOTO_RETENTION_DAYS ?? 90);

/// A scan nobody confirmed, and a file nothing points at, wait this long — enough for a person
/// who is still looking at the confirm sheet, and for a scan whose row is being written.
const PENDING_MS = DAY_MS;

/// D-240. Deletes the meal photos nothing should still hold. Three passes, each safe to repeat:
///  1. scans never confirmed — the photo of a plate the user said nothing about;
///  2. entry photos past the retention window — the entry stays, the picture goes;
///  3. files no row points at — an undone entry, an erased account (the rows cascade, the files
///     do not), or a crash between writing a file and its row.
///
/// The work only; [MealPhotoScheduler] is the clock (the subscription sweep's split), so a test —
/// or an operator at a console — can run it without waiting for tonight.
@Injectable()
export class MealPhotoSweep {
  constructor(
    @InjectRepository(FoodScanEntity)
    private readonly scans: Repository<FoodScanEntity>,
    @InjectRepository(FoodLogEntity)
    private readonly logs: Repository<FoodLogEntity>,
  ) {}

  async run(now: Date): Promise<number> {
    let removed = 0;

    const stale = await this.scans.find({
      where: {
        foodLogId: IsNull(),
        photoPath: Not(IsNull()),
        createdAt: LessThan(new Date(now.getTime() - PENDING_MS)),
      },
    });
    for (const scan of stale) {
      await deleteMealPhoto(scan.photoPath!);
      await this.scans.update(scan.id, { photoPath: null, estimate: null });
      removed++;
    }

    const expired = await this.logs.find({
      where: {
        photoPath: Not(IsNull()),
        loggedAt: LessThan(new Date(now.getTime() - retentionDays() * DAY_MS)),
      },
      select: { id: true, photoPath: true },
    });
    for (const entry of expired) {
      await deleteMealPhoto(entry.photoPath!);
      await this.logs.update(entry.id, { photoPath: null });
      removed++;
    }

    const [scanRefs, logRefs] = await Promise.all([
      this.scans.find({
        where: { photoPath: Not(IsNull()) },
        select: { id: true, photoPath: true },
      }),
      this.logs.find({
        where: { photoPath: Not(IsNull()) },
        select: { id: true, photoPath: true },
      }),
    ]);
    const referenced = new Set(
      [...scanRefs, ...logRefs].map((r) => r.photoPath),
    );
    for (const file of await listMealPhotos()) {
      const oldEnough = now.getTime() - file.modified.getTime() > PENDING_MS;
      if (!referenced.has(file.name) && oldEnough) {
        await deleteMealPhoto(file.name);
        removed++;
      }
    }

    return removed;
  }
}
