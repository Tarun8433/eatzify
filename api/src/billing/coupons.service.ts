import {
  Injectable,
  UnprocessableEntityException,
  HttpStatus,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { CouponEntity } from './entities/coupon.entity';

export interface CouponView {
  code: string;
  percent_off: number;
  max_uses: number;
  used_count: number;
  expires_at: string | null;
  active: boolean;
}

/// One place to shape a code, so "diwali50 " and "DIWALI50" are the same offer.
function normalize(code: string): string {
  return code.trim().toUpperCase();
}

const CODE_SHAPE = /^[A-Z0-9_-]{3,24}$/;

/// D-236 — the offers an admin hands out and the checkout honours.
@Injectable()
export class CouponsService {
  constructor(
    @InjectRepository(CouponEntity)
    private readonly coupons: Repository<CouponEntity>,
  ) {}

  /**
   * The discount a code is worth on [amountPaise] right now, or null when the code buys nothing —
   * unknown, switched off, expired or fully used. One null for every reason: which check failed
   * is the admin's business, not something checkout copy should leak.
   */
  async discountFor(
    code: string,
    amountPaise: bigint,
    now: Date,
  ): Promise<{ code: string; discountPaise: bigint } | null> {
    const row = await this.coupons.findOne({
      where: { code: normalize(code) },
    });
    if (!row || !row.active) return null;
    if (row.expiresAt !== null && row.expiresAt.getTime() < now.getTime())
      return null;
    if (row.usedCount >= row.maxUses) return null;

    // Integer paise all the way (api rule 3); floor by construction.
    const discountPaise = (amountPaise * BigInt(row.percentOff)) / 100n;
    return { code: row.code, discountPaise };
  }

  /// Called from the ONE place that grants a subscription (the verified webhook), so an
  /// abandoned checkout never consumes a use.
  async redeem(code: string): Promise<void> {
    await this.coupons.increment({ code: normalize(code) }, 'usedCount', 1);
  }

  async list(): Promise<CouponView[]> {
    const rows = await this.coupons.find({ order: { createdAt: 'DESC' } });
    return rows.map((r) => this.toView(r));
  }

  async create(input: {
    code: string;
    percent_off: number;
    max_uses: number;
    expires_at?: string | null;
  }): Promise<CouponView> {
    const code = normalize(input.code ?? '');
    const pct = Number(input.percent_off);
    const uses = Number(input.max_uses);
    const expiresAt = input.expires_at ? new Date(input.expires_at) : null;

    if (!CODE_SHAPE.test(code))
      this.reject('Code must be 3–24 letters, digits, - or _.');
    if (!Number.isInteger(pct) || pct < 1 || pct > 90) {
      this.reject('Percent off must be a whole number between 1 and 90.');
    }
    if (!Number.isInteger(uses) || uses < 1)
      this.reject('Max uses must be at least 1.');
    if (expiresAt !== null && Number.isNaN(expiresAt.getTime())) {
      this.reject('Expiry must be a valid date.');
    }
    if (await this.coupons.findOne({ where: { code } })) {
      this.reject('That code already exists.');
    }

    const row = await this.coupons.save(
      this.coupons.create({ code, percentOff: pct, maxUses: uses, expiresAt }),
    );
    return this.toView(row);
  }

  /// Deactivation, never deletion: a code that was ever live stays visible with its usage.
  async deactivate(code: string): Promise<CouponView> {
    const row = await this.coupons.findOne({
      where: { code: normalize(code) },
    });
    if (!row) this.reject('No such code.');
    row!.active = false;
    return this.toView(await this.coupons.save(row!));
  }

  private toView(r: CouponEntity): CouponView {
    return {
      code: r.code,
      percent_off: r.percentOff,
      max_uses: r.maxUses,
      used_count: r.usedCount,
      expires_at: r.expiresAt?.toISOString() ?? null,
      active: r.active,
    };
  }

  private reject(userMessage: string): never {
    throw new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code: 'COUPON_REJECTED', user_message: userMessage },
    });
  }
}
