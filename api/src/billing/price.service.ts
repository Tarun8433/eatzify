import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { TierPriceEntity } from './entities/tier-price.entity';
import { PRICES, type Tier } from './tiers';

export type PriceMatrix = typeof PRICES;
type PaidTier = Exclude<Tier, 'FREE'>;
type Duration = keyof PriceMatrix['PRO'];

/// How long an admin's price change can take to reach checkout.
const CACHE_TTL_MS = 60_000;

/// What Cashfree charges, from `tier_price` (payments plan, Phase 3). A cell missing from the
/// table falls back to the price `tiers.ts` shipped with, so a deleted row never makes a plan
/// unbuyable. Only the charged amounts read this; ranking tiers still uses `tiers.ts`.
@Injectable()
export class PriceService {
  // ponytail: per-process cache; one API container today. Add an explicit bust if that changes.
  private cached: { at: number; matrix: PriceMatrix } | null = null;

  constructor(
    @InjectRepository(TierPriceEntity)
    private readonly rows: Repository<TierPriceEntity>,
  ) {}

  async matrix(now = Date.now()): Promise<PriceMatrix> {
    if (this.cached && now - this.cached.at < CACHE_TTL_MS) {
      return this.cached.matrix;
    }
    const matrix: PriceMatrix = {
      BASIC: { ...PRICES.BASIC },
      PRO: { ...PRICES.PRO },
    };
    for (const row of await this.rows.find()) {
      const cells = matrix[row.tier as PaidTier] as
        Record<string, number> | undefined;
      if (cells && row.duration in cells) {
        cells[row.duration] = Number(row.pricePaise);
      }
    }
    this.cached = { at: now, matrix };
    return matrix;
  }

  async priceOf(tier: Tier, duration: string): Promise<number | undefined> {
    const matrix = await this.matrix();
    return matrix[tier as PaidTier]?.[duration as Duration];
  }
}
