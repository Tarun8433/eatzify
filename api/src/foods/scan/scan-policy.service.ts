import {
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { BillingService } from '../../billing/billing.service';
import { TIERS, type Tier } from '../../billing/tiers';
import { diaryDateFor } from '../../plans/diary-date';
import { UserEntity } from '../../users/infrastructure/persistence/relational/entities/user.entity';
import { FoodScanEntity } from './food-scan.entity';
import { ScanPolicyEntity } from './scan-policy.entity';
import type { PlateEstimate } from './plate-estimate';

const DAY_MS = 24 * 60 * 60 * 1000;

export type ScanDenial = 'disabled' | 'trial_over' | 'limit_reached';

/// What the app needs before opening the camera: may this person scan now, how many are left
/// today, and whether an ad comes first. The SERVER decides all of it (CLAUDE.md rule 3).
export type ScanStatus = {
  allowed: boolean;
  reason: ScanDenial | null;
  tier: Tier;
  daily_limit: number;
  remaining_today: number;
  requires_ad: boolean;
  /// When a tier's window closes (FREE's first days); null is no window.
  trial_ends_at: string | null;
  /// Why not, in the words to show — null when allowed (rule 7: the app renders the server's copy).
  user_message: string | null;
};

/// One wording per denial, shared by the status the app reads first and the error a scan throws.
const DENIAL_COPY: Record<ScanDenial, (limit: number) => string> = {
  disabled: () => 'Meal scanning is not part of your plan right now.',
  trial_over: () =>
    'Your free meal scans have ended. Upgrade to keep scanning your meals.',
  limit_reached: (limit) =>
    `You've used today's ${limit} meal scans. You can scan again tomorrow, or search for your food.`,
};

export type ScanPolicyView = {
  tier: Tier;
  enabled: boolean;
  daily_limit: number;
  requires_ad: boolean;
  trial_days: number | null;
  updated_at: string;
};

export type ScanPolicyPatch = Partial<{
  enabled: boolean;
  daily_limit: number;
  requires_ad: boolean;
  trial_days: number | null;
}>;

/// D-238. The admin-edited per-tier scan rules, and the check every scan passes first.
@Injectable()
export class ScanPolicyService {
  constructor(
    @InjectRepository(ScanPolicyEntity)
    private readonly policies: Repository<ScanPolicyEntity>,
    @InjectRepository(FoodScanEntity)
    private readonly scans: Repository<FoodScanEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    private readonly billing: BillingService,
  ) {}

  async status(userId: number, now = new Date()): Promise<ScanStatus> {
    const { tier } = await this.billing.entitlements(userId);
    const [policy, user, used] = await Promise.all([
      this.policies.findOneBy({ tier }),
      this.users.findOne({
        where: { id: userId },
        select: { id: true, createdAt: true },
      }),
      this.scans.count({ where: { userId, diaryDate: diaryDateFor(now) } }),
    ]);

    // A tier with no row is a tier nobody configured — closed, not open.
    const enabled = policy?.enabled ?? false;
    const dailyLimit = policy?.dailyLimit ?? 0;
    const trialEnds =
      policy?.trialDays != null && user
        ? new Date(user.createdAt.getTime() + policy.trialDays * DAY_MS)
        : null;
    const remaining = Math.max(0, dailyLimit - used);

    const reason: ScanDenial | null = !enabled
      ? 'disabled'
      : trialEnds && now >= trialEnds
        ? 'trial_over'
        : remaining === 0
          ? 'limit_reached'
          : null;

    return {
      allowed: reason === null,
      reason,
      tier,
      daily_limit: dailyLimit,
      remaining_today: remaining,
      requires_ad: policy?.requiresAd ?? false,
      trial_ends_at: trialEnds?.toISOString() ?? null,
      user_message: reason ? DENIAL_COPY[reason](dailyLimit) : null,
    };
  }

  /// Throws the envelope the app acts on: `ENTITLEMENT_REQUIRED` opens the upgrade sheet (rule 3),
  /// `SCAN_LIMIT_REACHED` and `AD_REQUIRED` carry the words to show.
  async assertAllowed(userId: number, adWatched: boolean): Promise<ScanStatus> {
    const status = await this.status(userId);

    if (status.reason === 'disabled' || status.reason === 'trial_over') {
      throw new ForbiddenException({
        status: HttpStatus.FORBIDDEN,
        error: {
          code: 'ENTITLEMENT_REQUIRED',
          user_message: status.user_message,
          details: { entitlement: 'food.scan' },
        },
      });
    }
    if (status.reason === 'limit_reached') {
      throw new HttpException(
        {
          status: HttpStatus.TOO_MANY_REQUESTS,
          error: {
            code: 'SCAN_LIMIT_REACHED',
            user_message: status.user_message,
          },
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    if (status.requires_ad && !adWatched) {
      throw new ForbiddenException({
        status: HttpStatus.FORBIDDEN,
        error: {
          code: 'AD_REQUIRED',
          user_message: 'Watch a short ad to scan this meal.',
        },
      });
    }
    return status;
  }

  /// ponytail: counted after the scan, so two scans fired at the same instant can both pass with
  /// one left — a one-scan overshoot at worst. A row lock per user if that ever costs money.
  async record(
    userId: number,
    scan: {
      matched: boolean;
      photoPath?: string | null;
      estimate?: PlateEstimate | null;
    },
  ): Promise<number> {
    const saved = await this.scans.save({
      userId,
      diaryDate: diaryDateFor(new Date()),
      matched: scan.matched,
      photoPath: scan.photoPath ?? null,
      estimate: scan.estimate ?? null,
    });
    return saved.id;
  }

  async list(): Promise<ScanPolicyView[]> {
    const rows = await this.policies.find();
    return TIERS.map((t) => rows.find((r) => r.tier === t))
      .filter((r): r is ScanPolicyEntity => r !== undefined)
      .map(toView);
  }

  async update(tier: string, patch: ScanPolicyPatch): Promise<ScanPolicyView> {
    const row = await this.policies.findOneBy({ tier: tier as Tier });
    if (!row) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: {
          code: 'SCAN_POLICY_NOT_FOUND',
          user_message: 'No such plan tier.',
        },
      });
    }
    const saved = await this.policies.save({
      ...row,
      enabled: patch.enabled ?? row.enabled,
      dailyLimit: patch.daily_limit ?? row.dailyLimit,
      requiresAd: patch.requires_ad ?? row.requiresAd,
      // `null` is a real value here (no window), so only an absent key keeps the old one.
      trialDays:
        patch.trial_days === undefined ? row.trialDays : patch.trial_days,
    });
    return toView(saved);
  }
}

const toView = (r: ScanPolicyEntity): ScanPolicyView => ({
  tier: r.tier,
  enabled: r.enabled,
  daily_limit: r.dailyLimit,
  requires_ad: r.requiresAd,
  trial_days: r.trialDays,
  updated_at: r.updatedAt.toISOString(),
});
