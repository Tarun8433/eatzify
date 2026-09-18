import {
  ForbiddenException,
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { ILike, In, Repository } from 'typeorm';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { HealthProfileEntity } from '../profile/entities/health-profile.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { FoodLogEntity } from '../logs/entities/food-log.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { maskPhone } from './admin-clients.service';
import type { ContentClass } from '../notifications/entities/notification.entity';

/// docs/09 §9's search body. A `condition` is a health field, which is why the whole thing is a
/// POST (api rule 6) and why searching by one is an audited read (docs/10 §4).
export type UserFilters = {
  tier?: string;
  goal?: string;
  conditions?: string[];
  /// Nobody has logged anything for this many days.
  inactive_days?: number;
};

export type UserSearchRow = {
  user_id: number;
  name: string;
  goal: string;
  tier: string;
  phone_masked: string | null;
  last_logged_date: string | null;
};

/// docs/09 §9's segment, and docs/13 §5's one hard rule about it.
export type Segment = UserFilters & { user_ids?: number[] };

export type BroadcastResult = {
  /// How many people it actually reached. A segment that matched nobody says zero rather than
  /// pretending it went out.
  sent: number;
  content_class: ContentClass;
};

/// The most a search returns at once, and the most one broadcast may reach without being split.
export const MAX_SEARCH_ROWS = 100;
export const MAX_BROADCAST = 5000;

/**
 * Finding people, and sending them something (docs/09 §9).
 *
 * **docs/13 §5 is the rule this service exists to hold:** a notification may be targeted by health
 * CONDITION only when it is clinical. A commercial message aimed at people with diabetes is exactly
 * what the DPDP work forbids, and a rule that lives only in a document is one that ships broken.
 */
@Injectable()
export class AdminAudienceService {
  constructor(
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    @InjectRepository(HealthProfileEntity)
    private readonly health: Repository<HealthProfileEntity>,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(FoodLogEntity)
    private readonly logs: Repository<FoodLogEntity>,
    private readonly notifications: NotificationsService,
  ) {}

  /// Whether this search reads a health field, and therefore needs a reason and an audit row.
  static readsHealth(filters: UserFilters | undefined): boolean {
    return (filters?.conditions?.length ?? 0) > 0;
  }

  async search(
    query: string | undefined,
    filters: UserFilters | undefined,
    now: Date,
  ): Promise<UserSearchRow[]> {
    const ids = await this.matching(query, filters, now);
    if (ids.length === 0) return [];

    const page = ids.slice(0, MAX_SEARCH_ROWS);
    const [profiles, users, subs] = await Promise.all([
      this.profiles.find({ where: { userId: In(page) } }),
      this.users.find({ where: { id: In(page) } }),
      this.subscriptions.find({ where: { userId: In(page) } }),
    ]);

    // An id that matched nothing is not a person. A typed number that happens to look like an id
    // must not produce a row for an account nobody has.
    const exists = new Set([
      ...profiles.map((p) => p.userId),
      ...users.map((u) => u.id),
    ]);
    const found = page.filter((id) => exists.has(id));

    const profileOf = new Map(profiles.map((p) => [p.userId, p]));
    const phoneOf = new Map(users.map((u) => [u.id, u.phone ?? null]));
    const tierOf = new Map(subs.map((s) => [s.userId, s.tier]));

    return Promise.all(
      found.map(async (userId) => ({
        user_id: userId,
        name: profileOf.get(userId)?.name ?? `Client ${userId}`,
        goal: profileOf.get(userId)?.goal ?? '',
        tier: tierOf.get(userId) ?? 'FREE',
        // docs/13 §4: a list view masks. The full number is on the detail read, behind a reason.
        phone_masked: maskPhone(phoneOf.get(userId) ?? null),
        last_logged_date: await this.lastLogged(userId),
      })),
    );
  }

  /**
   * docs/09 §9's `POST /admin/notifications`.
   *
   * The one refusal that matters: `segment.condition` is allowed only when the message is clinical
   * (docs/13 §5). Everything else here is arithmetic about who matched.
   */
  async broadcast(
    input: {
      title: string;
      body: string;
      contentClass: ContentClass;
      segment?: Segment;
    },
    now: Date,
  ): Promise<BroadcastResult> {
    const byCondition = (input.segment?.conditions?.length ?? 0) > 0;
    if (byCondition && input.contentClass !== 'clinical') {
      throw new ForbiddenException({
        status: HttpStatus.FORBIDDEN,
        error: {
          code: 'CONDITION_TARGETING_FORBIDDEN',
          user_message:
            'Only a clinical message may be sent to people by health condition (docs/13 §5).',
        },
      });
    }

    const ids = input.segment?.user_ids?.length
      ? input.segment.user_ids
      : await this.matching(undefined, input.segment, now);

    if (ids.length > MAX_BROADCAST) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'SEGMENT_TOO_LARGE',
          user_message: `That segment reaches ${ids.length} people. Narrow it to ${MAX_BROADCAST} or fewer.`,
        },
      });
    }

    // One key per person per send, so a retried request does not arrive twice.
    const key = `admin:${now.getTime()}`;
    let sent = 0;
    for (const userId of ids) {
      const saved = await this.notifications.notify({
        userId,
        kind: 'admin_broadcast',
        contentClass: input.contentClass,
        title: input.title,
        body: input.body,
        dedupeKey: key,
      });
      if (saved) sent++;
    }

    return { sent, content_class: input.contentClass };
  }

  /// Who matches, as user ids. Kept apart from the two callers because "who is in this segment" is
  /// the same question whether it is being listed or messaged.
  private async matching(
    query: string | undefined,
    filters: UserFilters | undefined,
    now: Date,
  ): Promise<number[]> {
    let ids: number[] | null = null;

    const text = query?.trim();
    if (text) {
      // A user id is an int4 — nine digits at most. Without this, searching for a PHONE number
      // matched "user 9000000002" as well, and the page carried a row for somebody who does not
      // exist.
      const asId = /^\d{1,9}$/.test(text) ? Number(text) : Number.NaN;

      const [byName, byPhone] = await Promise.all([
        this.profiles.find({ where: { name: ILike(`%${text}%`) } }),
        this.users.find({ where: { phone: ILike(`%${text}%`) } }),
      ]);

      ids = [
        ...new Set([
          ...byName.map((p) => p.userId),
          ...byPhone.map((u) => u.id),
          ...(Number.isInteger(asId) && asId > 0 ? [asId] : []),
        ]),
      ];
    }

    if (filters?.goal) {
      const rows = await this.profiles.find({ where: { goal: filters.goal } });
      ids = intersect(
        ids,
        rows.map((p) => p.userId),
      );
    }

    if (filters?.tier) {
      const rows = await this.subscriptions.find({
        where: { tier: filters.tier },
      });
      ids = intersect(
        ids,
        rows.map((s) => s.userId),
      );
    }

    if (filters?.conditions?.length) {
      // The LATEST health profile per user, because conditions are versioned and an old version
      // saying "diabetes" is not what this person declares today.
      const rows = await this.health.find({ order: { version: 'DESC' } });
      const seen = new Set<number>();
      const matched: number[] = [];
      for (const row of rows) {
        if (seen.has(row.userId)) continue;
        seen.add(row.userId);
        if (row.conditions.some((c) => filters.conditions!.includes(c))) {
          matched.push(row.userId);
        }
      }
      ids = intersect(ids, matched);
    }

    if (filters?.inactive_days !== undefined) {
      const quiet = await this.quietSince(filters.inactive_days, now);
      ids = intersect(ids, quiet);
    }

    // No query and no filters: everybody with a profile, which is what an "all users" send means.
    if (ids === null) {
      const all = await this.profiles.find();
      return all.map((p) => p.userId);
    }

    return ids;
  }

  /// Everyone with a profile who has logged nothing in the last [days] days.
  private async quietSince(days: number, now: Date): Promise<number[]> {
    const [profiles, logs] = await Promise.all([
      this.profiles.find(),
      this.logs.find({ order: { diaryDate: 'DESC' } }),
    ]);

    const cutoff = new Date(now.getTime() - days * 86_400_000)
      .toISOString()
      .slice(0, 10);
    const recent = new Set(
      logs.filter((l) => l.diaryDate >= cutoff).map((l) => l.userId),
    );

    return profiles.map((p) => p.userId).filter((id) => !recent.has(id));
  }

  private async lastLogged(userId: number): Promise<string | null> {
    const row = await this.logs.findOne({
      where: { userId },
      order: { diaryDate: 'DESC' },
    });
    return row?.diaryDate ?? null;
  }
}

/// Null means "nothing has narrowed this yet", which is not the same as an empty match.
function intersect(current: number[] | null, next: number[]): number[] {
  if (current === null) return [...new Set(next)];
  const allowed = new Set(next);
  return current.filter((id) => allowed.has(id));
}
