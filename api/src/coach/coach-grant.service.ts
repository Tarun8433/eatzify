import {
  ForbiddenException,
  HttpStatus,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { LessThan, Repository } from 'typeorm';
import {
  CoachGrantEntity,
  type GrantScope,
} from './entities/coach-grant.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { RoleEnum } from '../roles/roles.enum';

/// docs/10 §3 and §1. What each coach level's grant may CONTAIN — the level caps the scopes, it
/// never grants them.
///
/// `coach_l1` is absent, and that absence is the design: an affiliate is a referrer with "no
/// coaching relationship" (§1), so there is nothing for a grant to attach to. Anyone who accepted
/// an agreement and shared a link would otherwise be reading a stranger's weight history.
const SCOPES_BY_ROLE: Readonly<
  Partial<Record<RoleEnum, readonly GrantScope[]>>
> = {
  [RoleEnum.coach_l2]: ['basic', 'progress', 'plan_view'],
  [RoleEnum.coach_l3]: [
    'basic',
    'progress',
    'plan_view',
    'plan_edit',
    'chat',
    'health_conditions',
  ],
};

/// docs/10 §3: "default expiry = subscription end date, or 180 days, whichever is sooner."
const MAX_GRANT_DAYS = 180;

export type GrantView = {
  coach_user_id: number;
  scopes: GrantScope[];
  status: string;
  expires_at: string;
};

/**
 * Consent grants — the only thing that lets one person see another's health data (docs/10 §1).
 *
 * Every method here exists to keep one sentence true: **a coach may request a scope; only the
 * client may grant it.** So the client id is never taken from a body, a coach's own level caps
 * what their grant may hold, and revocation is immediate and unconditional.
 */
@Injectable()
export class CoachGrantService {
  constructor(
    @InjectRepository(CoachGrantEntity)
    private readonly grants: Repository<CoachGrantEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
  ) {}

  /**
   * The client grants a coach a set of scopes.
   *
   * [clientUserId] comes from the authenticated caller and never from a request body — accepting
   * it as input would let anyone grant anyone's data away.
   */
  async grant({
    clientUserId,
    coachUserId,
    scopes,
    subscriptionEndsAt,
    now,
  }: {
    clientUserId: number;
    coachUserId: number;
    scopes: readonly GrantScope[];
    subscriptionEndsAt?: Date | null;
    now: Date;
  }): Promise<GrantView> {
    if (clientUserId === coachUserId) {
      throw this.refuse(
        'INVALID_GRANT',
        'You cannot add yourself as your own coach.',
      );
    }

    await this.assertScopesWithinLevel(coachUserId, scopes);

    const existing = await this.grants.findOne({
      where: { clientUserId, coachUserId },
    });

    const saved = await this.grants.save({
      ...(existing ?? {}),
      clientUserId,
      coachUserId,
      // Replaced, not merged. The client is answering "what may this person see" afresh, and
      // merging would make it impossible to take a scope back by re-granting a smaller set.
      scopes: [...scopes],
      status: 'active' as const,
      expiresAt: this.expiryFor(subscriptionEndsAt, now),
      endedReason: null,
      endedAt: null,
    });

    return this.toView(saved as CoachGrantEntity);
  }

  /**
   * The client takes access back. One tap, effective immediately (docs/10 §3).
   *
   * `paused`, never deleted: the coach's screen has to be able to say "access ended" rather than
   * keep showing what it last cached, and a deleted row cannot say anything.
   */
  async revoke(
    clientUserId: number,
    coachUserId: number,
    now: Date,
  ): Promise<void> {
    await this.grants.update(
      { clientUserId, coachUserId },
      { status: 'paused', endedReason: 'revoked_by_client', endedAt: now },
    );
  }

  /// Everything the client has given away, for the "Who can see my data" screen docs/10 §3 asks
  /// for. Paused rows included — what access USED to exist is part of the answer.
  async forClient(clientUserId: number): Promise<GrantView[]> {
    const rows = await this.grants.find({ where: { clientUserId } });
    return rows.map((r) => this.toView(r));
  }

  /**
   * The scopes this coach currently holds over this client, or an empty list.
   *
   * The single question every coach-facing read must ask. An expired grant answers empty even
   * before the sweep has run, because an expiry that depends on a cron job having fired is not
   * an expiry.
   */
  async scopesFor(
    coachUserId: number,
    clientUserId: number,
    now: Date,
  ): Promise<GrantScope[]> {
    const row = await this.grants.findOne({
      where: { clientUserId, coachUserId },
    });

    if (!row || row.status !== 'active' || row.expiresAt <= now) return [];

    /**
     * Intersected with the coach's level as it stands RIGHT NOW, not as it stood when the client
     * agreed.
     *
     * A coach demoted after being granted `health_conditions` must lose it the moment they are
     * demoted — without anyone rewriting the grant rows, which is a job that can fail or lag. The
     * cap at grant time stops a level-1 coach ever being given it; this stops a former level-3
     * coach keeping it.
     */
    const allowed = await this.allowedScopesFor(coachUserId);
    return row.scopes.filter((scope) => allowed.includes(scope));
  }

  /// Moves lapsed grants to `paused` so the coach's list stops showing them. Reads already treat
  /// an expired grant as absent, so this is tidying rather than enforcement.
  async expireLapsed(now: Date): Promise<number> {
    const result = await this.grants.update(
      { status: 'active', expiresAt: LessThan(now) },
      { status: 'paused', endedReason: 'expired', endedAt: now },
    );

    return result.affected ?? 0;
  }

  /**
   * The coach's level reaches every one of these scopes, or nothing happens.
   *
   * Public because the INVITE has to apply the same cap at the ask (docs/09 §6): a coach should be
   * told their level is too low when they invite, rather than leaving the client to hit it on
   * accept. One rule, two callers — two copies of it would eventually disagree.
   */
  async assertScopesWithinLevel(
    coachUserId: number,
    scopes: readonly GrantScope[],
  ): Promise<void> {
    const allowed = await this.allowedScopesFor(coachUserId);
    const refused = scopes.filter((s) => !allowed.includes(s));
    if (refused.length === 0) return;

    // A level the scope outruns is not a smaller grant — it is the wrong coach for the request,
    // and silently trimming it would hand the client a grant they did not agree to.
    throw new ForbiddenException({
      status: HttpStatus.FORBIDDEN,
      error: {
        code: 'SCOPE_ABOVE_COACH_LEVEL',
        // Addressed to the CALLER, who is the coach doing the asking. The old wording — "this
        // partner is not verified... ask them to complete verification" — described somebody
        // else, so a coach_l1 refused for `basic` read it as the CLIENT needing to verify and
        // went looking for a problem on the other side.
        user_message:
          'Your partner level does not cover everything you asked for. Complete verification to request this.',
        details: { refused },
      },
    });
  }

  private async allowedScopesFor(
    coachUserId: number,
  ): Promise<readonly GrantScope[]> {
    const coach = await this.users.findOne({ where: { id: coachUserId } });
    const role = coach?.role?.id as RoleEnum | undefined;

    return role === undefined ? [] : (SCOPES_BY_ROLE[role] ?? []);
  }

  /// docs/10 §3: subscription end, or 180 days, whichever is sooner.
  private expiryFor(subscriptionEndsAt: Date | null | undefined, now: Date) {
    const ceiling = new Date(now);
    ceiling.setDate(ceiling.getDate() + MAX_GRANT_DAYS);

    if (!subscriptionEndsAt) return ceiling;
    return subscriptionEndsAt < ceiling ? subscriptionEndsAt : ceiling;
  }

  private refuse(code: string, userMessage: string): Error {
    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      error: { code, user_message: userMessage },
    });
  }

  private toView(row: CoachGrantEntity): GrantView {
    return {
      coach_user_id: row.coachUserId,
      scopes: row.scopes,
      status: row.status,
      expires_at: row.expiresAt.toISOString(),
    };
  }
}
