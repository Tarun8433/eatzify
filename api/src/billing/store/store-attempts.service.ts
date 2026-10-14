import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { MoreThan, Repository } from 'typeorm';
import {
  StorePurchaseAttemptEntity,
  type AttemptOutcome,
  type AttemptReason,
} from '../entities/store-purchase-attempt.entity';
import type { StoreProvider } from './store-rules';

/// D-266: at most this many attempts kept per user per hour. Past it the rest are dropped, quietly —
/// the app reports fire-and-forget and must never see this route fail.
export const MAX_ATTEMPTS_PER_HOUR = 30;
const HOUR_MS = 3_600_000;

/// Play's codes look like `BillingResponse.developerError`. Anything else is not stored.
const STORE_CODE = /^[A-Za-z0-9._:-]{1,80}$/;

export type StoreAttemptInput = {
  provider: StoreProvider;
  productId: string;
  basePlanId: string | null;
  offerId: string | null;
  outcome: AttemptOutcome;
  reason: AttemptReason | null;
  storeCode: string | null;
};

export function cleanStoreCode(code: string | null | undefined): string | null {
  return code && STORE_CODE.test(code) ? code : null;
}

@Injectable()
export class StoreAttemptsService {
  constructor(
    @InjectRepository(StorePurchaseAttemptEntity)
    private readonly attempts: Repository<StorePurchaseAttemptEntity>,
  ) {}

  /// Returns whether the attempt was kept.
  async record(
    userId: number,
    input: StoreAttemptInput,
    now = new Date(),
  ): Promise<boolean> {
    // ponytail: count-then-insert, the same as the email-code limit; a burst can overshoot by a
    // few rows, which is harmless here.
    const recent = await this.attempts.count({
      where: { userId, createdAt: MoreThan(new Date(now.getTime() - HOUR_MS)) },
    });
    if (recent >= MAX_ATTEMPTS_PER_HOUR) return false;

    await this.attempts.save(
      this.attempts.create({
        ...input,
        userId,
        storeCode: cleanStoreCode(input.storeCode),
      }),
    );
    return true;
  }
}
