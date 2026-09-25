import {
  BadRequestException,
  HttpStatus,
  Inject,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { LogsService, type LogEntryView } from '../../logs/logs.service';
import { deleteMealPhoto, saveMealPhoto } from '../../logs/meal-photo';
import type { NutritionView } from '../../logs/nutrition-for';
import { FoodScanEntity } from './food-scan.entity';
import {
  FOOD_VISION_PROVIDER,
  type FoodVisionProvider,
  type ScanImageType,
} from './food-vision.provider';
import { sumItems, type EstimatedItem } from './plate-estimate';
import { ScanPolicyService } from './scan-policy.service';

const IMAGE_TYPES: Record<string, 'jpg' | 'png'> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
};

/// What the app shows under "Are you having this?". `scan_id` is null when the photo was not food.
export type ScanResult = {
  scan_id: number | null;
  dish_name: string;
  confidence: number;
  items: EstimatedItem[];
  totals: NutritionView;
};

/// D-240. Photo → the model's estimate of the plate → "Are you having this?" → ONE diary entry with
/// the nutrition of the items kept and the user's own photo. Nothing is logged without "yes".
@Injectable()
export class FoodScanService {
  private readonly logger = new Logger(FoodScanService.name);

  constructor(
    @Inject(FOOD_VISION_PROVIDER)
    private readonly vision: FoodVisionProvider | null,
    private readonly policy: ScanPolicyService,
    private readonly logs: LogsService,
    @InjectRepository(FoodScanEntity)
    private readonly scans: Repository<FoodScanEntity>,
  ) {}

  async scan(
    userId: number,
    image: Express.Multer.File | undefined,
    adWatched: boolean,
  ): Promise<ScanResult> {
    if (!this.vision) throw unavailable();
    const ext = image ? IMAGE_TYPES[image.mimetype] : undefined;
    if (!image || !ext) {
      throw new BadRequestException({
        status: HttpStatus.BAD_REQUEST,
        error: {
          code: 'SCAN_IMAGE_INVALID',
          user_message: 'Please use a JPG or PNG photo.',
        },
      });
    }

    await this.policy.assertAllowed(userId, adWatched);

    let estimate;
    try {
      estimate = await this.vision.estimate(
        image.buffer,
        image.mimetype as ScanImageType,
      );
    } catch (e) {
      // Class and message, capped — never the request: it carried a user's meal photo (api rule 5).
      // The providers' own messages are a status or a network reason, which is what the log needs.
      const err = e as Error;
      this.logger.error(
        `food vision failed: ${err.constructor.name}: ${String(err.message).slice(0, 200)}`,
      );
      throw unavailable();
    }

    if (!estimate.isFood) {
      await this.policy.record(userId, { matched: false });
      return {
        scan_id: null,
        dish_name: '',
        confidence: 0,
        items: [],
        totals: sumItems([]),
      };
    }

    // Kept only now there is something to confirm — a photo of nothing is never stored. Private,
    // and deleted within a day unless "yes" hands it to a diary entry (the sweep).
    const photoPath = await saveMealPhoto(image.buffer, ext);
    const scanId = await this.policy.record(userId, {
      matched: true,
      photoPath,
      estimate,
    });

    return {
      scan_id: scanId,
      dish_name: estimate.dishName,
      confidence: estimate.confidence,
      items: estimate.items,
      totals: sumItems(estimate.items),
    };
  }

  /// "Yes": the kept items, summed by the server from the stored estimate — the app sends WHICH
  /// items, never numbers — logged as one entry with the photo.
  async confirm(
    userId: number,
    scanId: number,
    slot: string,
    keep?: number[],
  ): Promise<LogEntryView> {
    const scan = await this.scans.findOne({ where: { id: scanId, userId } });
    const estimate = scan?.estimate;
    if (!scan || !estimate || scan.foodLogId || !scan.photoPath) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: {
          code: 'SCAN_NOT_FOUND',
          user_message: 'That scan has expired. Please take the photo again.',
        },
      });
    }

    const indexes = new Set(keep ?? estimate.items.map((_, i) => i));
    const kept = estimate.items.filter((_, i) => indexes.has(i));
    if (kept.length === 0) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'SCAN_NOTHING_KEPT',
          user_message:
            'Keep at least one item, or search for your food instead.',
        },
      });
    }

    const entry = await this.logs.logEstimate(userId, {
      slot,
      name:
        kept.length === estimate.items.length
          ? estimate.dishName
          : kept.map((i) => i.name).join(' + '),
      nutrition: sumItems(kept),
      photoPath: scan.photoPath,
    });
    // The photo belongs to the entry now; the scan row keeps only the link and the count.
    await this.scans.update(scan.id, { foodLogId: entry.id, photoPath: null });
    return entry;
  }

  /// "No": the photo goes at once rather than waiting for the sweep. Idempotent.
  async discard(userId: number, scanId: number): Promise<void> {
    const scan = await this.scans.findOne({ where: { id: scanId, userId } });
    if (!scan || scan.foodLogId) return;
    if (scan.photoPath) await deleteMealPhoto(scan.photoPath);
    await this.scans.update(scan.id, { photoPath: null, estimate: null });
  }
}

const unavailable = () =>
  new ServiceUnavailableException({
    status: HttpStatus.SERVICE_UNAVAILABLE,
    error: {
      code: 'SCAN_UNAVAILABLE',
      user_message:
        "Meal scanning isn't available right now. Search for your food instead.",
    },
  });
