import {
  Injectable,
  Optional,
  UnprocessableEntityException,
  HttpStatus,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { CouponEntity } from './entities/coupon.entity';
import { PaymentOrderEntity } from './entities/payment-order.entity';

export interface CouponView {
  code: string;
  percent_off: number;
  max_uses: number;
  used_count: number;
  expires_at: string | null;
  active: boolean;
  /// Admin panel plan, Phase C: the offer card.
  title: string | null;
  description: string | null;
  banner_url: string | null;
  starts_at: string | null;
  eligibility: 'all' | 'new_users';
  tier: 'BASIC' | 'PRO' | null;
}

/// What an admin may set on an offer, at creation or later.
export type OfferFields = {
  title?: string | null;
  description?: string | null;
  banner_url?: string | null;
  starts_at?: string | null;
  eligibility?: 'all' | 'new_users';
  tier?: 'BASIC' | 'PRO' | null;
};

export type OfferStats = {
  code: string;
  paid_orders: number;
  revenue_paise: string;
  discount_paise: string;
};

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
    // Phase C: "new users only" and per-offer stats read the orders. Optional so older unit tests
    // need not supply it; a new-users offer is refused without it rather than allowed.
    @Optional()
    @InjectRepository(PaymentOrderEntity)
    private readonly orders: Repository<PaymentOrderEntity> | null = null,
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
    buyer?: { userId: number; tier: string },
  ): Promise<{ code: string; discountPaise: bigint } | null> {
    const row = await this.coupons.findOne({
      where: { code: normalize(code) },
    });
    if (!row || !row.active) return null;
    if (row.expiresAt !== null && row.expiresAt.getTime() < now.getTime())
      return null;
    if (row.startsAt && row.startsAt.getTime() > now.getTime()) return null;
    if (row.usedCount >= row.maxUses) return null;
    if (row.tier && buyer && row.tier !== buyer.tier) return null;
    if (row.eligibility === 'new_users') {
      if (!buyer || !this.orders) return null;
      const paidBefore = await this.orders.count({
        where: { userId: buyer.userId, status: In(['paid', 'refunded']) },
      });
      if (paidBefore > 0) return null;
    }

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

  async create(
    input: {
      code: string;
      percent_off: number;
      max_uses: number;
      expires_at?: string | null;
    } & OfferFields,
  ): Promise<CouponView> {
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
      this.coupons.create({
        code,
        percentOff: pct,
        maxUses: uses,
        expiresAt,
        ...this.offerFields(input),
      }),
    );
    return this.toView(row);
  }

  /// Phase C: change what an offer says and who may use it. The code, the percentage and the
  /// uses already spent stay as they are — changing those would rewrite what people were sold.
  async update(
    code: string,
    input: OfferFields & { max_uses?: number; expires_at?: string | null },
  ): Promise<CouponView> {
    const row = await this.coupons.findOne({
      where: { code: normalize(code) },
    });
    if (!row) this.reject('No such code.');
    if (input.max_uses !== undefined) {
      const uses = Number(input.max_uses);
      if (!Number.isInteger(uses) || uses < row!.usedCount || uses < 1) {
        this.reject(
          'Max uses must be a whole number, at least the uses already spent.',
        );
      }
      row!.maxUses = uses;
    }
    if (input.expires_at !== undefined) {
      row!.expiresAt = input.expires_at ? new Date(input.expires_at) : null;
    }
    Object.assign(row!, this.offerFields(input));
    return this.toView(await this.coupons.save(row!));
  }

  /// Per offer: how many paid orders used it, what they paid, and what it gave away.
  async stats(): Promise<OfferStats[]> {
    if (!this.orders) return [];
    const rows = await this.orders
      .createQueryBuilder('o')
      .select('o."couponCode"', 'code')
      .addSelect('COUNT(*)', 'n')
      .addSelect('COALESCE(SUM(o."amountPaise"), 0)', 'revenue')
      .addSelect('COALESCE(SUM(o."discountPaise"), 0)', 'discount')
      .where('o."couponCode" IS NOT NULL')
      .andWhere(`o.status IN ('paid', 'refunded')`)
      .groupBy('o."couponCode"')
      .getRawMany<{
        code: string;
        n: string;
        revenue: string;
        discount: string;
      }>();
    return rows.map((r) => ({
      code: r.code,
      paid_orders: Number(r.n),
      revenue_paise: String(r.revenue),
      discount_paise: String(r.discount),
    }));
  }

  private offerFields(input: OfferFields): Partial<CouponEntity> {
    const out: Partial<CouponEntity> = {};
    if (input.title !== undefined) out.title = input.title?.trim() || null;
    if (input.description !== undefined)
      out.description = input.description?.trim() || null;
    if (input.banner_url !== undefined)
      out.bannerUrl = input.banner_url?.trim() || null;
    if (input.starts_at !== undefined) {
      const at = input.starts_at ? new Date(input.starts_at) : null;
      if (at && Number.isNaN(at.getTime()))
        this.reject('Start must be a valid date.');
      out.startsAt = at;
    }
    if (input.eligibility !== undefined) {
      if (!['all', 'new_users'].includes(input.eligibility))
        this.reject('Unknown eligibility.');
      out.eligibility = input.eligibility;
    }
    if (input.tier !== undefined) {
      if (input.tier !== null && !['BASIC', 'PRO'].includes(input.tier))
        this.reject('Unknown tier.');
      out.tier = input.tier;
    }
    return out;
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
      title: r.title ?? null,
      description: r.description ?? null,
      banner_url: r.bannerUrl ?? null,
      starts_at: r.startsAt?.toISOString() ?? null,
      eligibility: r.eligibility ?? 'all',
      tier: r.tier ?? null,
    };
  }

  private reject(userMessage: string): never {
    throw new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code: 'COUPON_REJECTED', user_message: userMessage },
    });
  }
}
