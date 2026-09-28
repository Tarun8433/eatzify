import { ForbiddenException } from '@nestjs/common';
import { CoachGrantService } from '../src/coach/coach-grant.service';
import type { CoachGrantEntity } from '../src/coach/entities/coach-grant.entity';
import { RoleEnum } from '../src/roles/roles.enum';

/// docs/10 §1 and §3. One sentence holds this whole file together: "the level does not grant
/// access. The consent grant does." A coach_l3 without a row sees nothing; a row may never hold a
/// scope the coach's level does not reach.

const NOW = new Date('2026-09-12T00:00:00Z');

function serviceWith({
  role = RoleEnum.coach_l3,
  existing = null as Partial<CoachGrantEntity> | null,
} = {}) {
  let row = existing as CoachGrantEntity | null;
  const updates: Record<string, unknown>[] = [];

  const service = new CoachGrantService(
    {
      findOne: () => Promise.resolve(row),
      find: () => Promise.resolve(row ? [row] : []),
      save: (next: CoachGrantEntity) => {
        row = { ...row, ...next } as CoachGrantEntity;
        return Promise.resolve(row);
      },
      update: (_where: unknown, patch: Record<string, unknown>) => {
        updates.push(patch);
        row = { ...row, ...patch } as CoachGrantEntity;
        return Promise.resolve({ affected: 1 });
      },
    } as never,
    { findOne: () => Promise.resolve({ id: 2, role: { id: role } }) } as never,
  );

  return { service, updates, current: () => row };
}

async function refusedCode(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (e as ForbiddenException).getResponse() as {
      error: { code: string };
    };
    return body.error.code;
  }
  throw new Error('expected the grant to be refused');
}

describe('a grant may not exceed the coach level', () => {
  /// §1: an affiliate is a referrer with "no coaching relationship", so there is nothing for a
  /// grant to attach to. Without this, anyone who accepted an agreement and shared a link would
  /// be reading a stranger's weight history — §5.1's lead-generation leak through another door.
  it('should refuse every scope when the coach is only an affiliate', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l1 });

    const code = await refusedCode(
      service.grant({
        clientUserId: 1,
        coachUserId: 2,
        scopes: ['basic'],
        now: NOW,
      }),
    );

    expect(code).toBe('SCOPE_ABOVE_COACH_LEVEL');
  });

  /// §2: a verified coach does not see medical conditions. "A verified coach with no coaching
  /// relationship has no need for a diabetes diagnosis, and giving it to them is processing
  /// without a purpose."
  it('should refuse health conditions when the coach is verified but not coaching', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l2 });

    const code = await refusedCode(
      service.grant({
        clientUserId: 1,
        coachUserId: 2,
        scopes: ['basic', 'health_conditions'],
        now: NOW,
      }),
    );

    expect(code).toBe('SCOPE_ABOVE_COACH_LEVEL');
  });

  /// Refusing the whole request, not trimming it. A silently smaller grant is one the client never
  /// agreed to and cannot see they did not get.
  it('should refuse the whole request rather than granting the part that fits', async () => {
    const { service, current } = serviceWith({ role: RoleEnum.coach_l2 });

    await refusedCode(
      service.grant({
        clientUserId: 1,
        coachUserId: 2,
        scopes: ['basic', 'plan_edit'],
        now: NOW,
      }),
    );

    expect(current()).toBeNull();
  });

  it('should allow the full set when the coach is a coaching partner', async () => {
    const { service } = serviceWith({ role: RoleEnum.coach_l3 });

    const view = await service.grant({
      clientUserId: 1,
      coachUserId: 2,
      scopes: ['basic', 'progress', 'health_conditions'],
      now: NOW,
    });

    expect(view.scopes).toEqual(['basic', 'progress', 'health_conditions']);
  });
});

describe('expiry (docs/10 §3)', () => {
  it('should cap a grant at 180 days when there is no subscription', async () => {
    const { service } = serviceWith();

    const view = await service.grant({
      clientUserId: 1,
      coachUserId: 2,
      scopes: ['basic'],
      now: NOW,
    });

    expect(view.expires_at).toBe('2027-03-11T00:00:00.000Z');
  });

  /// "Subscription end date, or 180 days, whichever is SOONER."
  it('should end with the subscription when that comes first', async () => {
    const { service } = serviceWith();

    const view = await service.grant({
      clientUserId: 1,
      coachUserId: 2,
      scopes: ['basic'],
      subscriptionEndsAt: new Date('2026-10-01T00:00:00Z'),
      now: NOW,
    });

    expect(view.expires_at).toBe('2026-10-01T00:00:00.000Z');
  });

  /// An expiry that only takes effect once a cron job has run is not an expiry. Reads answer
  /// empty the moment the clock passes it.
  it('should report no scopes past the expiry, before any sweep has run', async () => {
    const { service } = serviceWith({
      existing: {
        clientUserId: 1,
        coachUserId: 2,
        scopes: ['basic'],
        status: 'active',
        expiresAt: new Date('2026-09-01T00:00:00Z'),
      },
    });

    expect(await service.scopesFor(2, 1, NOW)).toEqual([]);
  });
});

describe('revocation is immediate and keeps the row', () => {
  /// §3: revocation "moves the assignment to `paused` and the coach's UI shows a neutral 'access
  /// ended' state, not the last-cached data". A deleted row cannot say anything at all.
  it('should pause rather than delete when the client revokes', async () => {
    const { service, updates } = serviceWith({
      existing: {
        clientUserId: 1,
        coachUserId: 2,
        scopes: ['basic'],
        status: 'active',
        expiresAt: new Date('2027-01-01T00:00:00Z'),
      },
    });

    await service.revoke(1, 2, NOW);

    expect(updates[0]).toMatchObject({
      status: 'paused',
      endedReason: 'revoked_by_client',
    });
  });

  it('should report no scopes once revoked', async () => {
    const { service } = serviceWith({
      existing: {
        clientUserId: 1,
        coachUserId: 2,
        scopes: ['basic', 'progress'],
        status: 'paused',
        expiresAt: new Date('2027-01-01T00:00:00Z'),
      },
    });

    expect(await service.scopesFor(2, 1, NOW)).toEqual([]);
  });
});

describe('re-granting answers the question again', () => {
  /// Replaced, not merged. Merging would make it impossible to take a scope back by re-granting a
  /// smaller set — the client would tap "only progress" and keep giving away their conditions.
  it('should replace the scopes rather than add to them', async () => {
    const { service } = serviceWith({
      existing: {
        clientUserId: 1,
        coachUserId: 2,
        scopes: ['basic', 'progress', 'health_conditions'],
        status: 'active',
        expiresAt: new Date('2027-01-01T00:00:00Z'),
      },
    });

    const view = await service.grant({
      clientUserId: 1,
      coachUserId: 2,
      scopes: ['progress'],
      now: NOW,
    });

    expect(view.scopes).toEqual(['progress']);
  });

  it('should refuse a grant to yourself', async () => {
    const { service } = serviceWith();

    await expect(
      service.grant({
        clientUserId: 1,
        coachUserId: 1,
        scopes: ['basic'],
        now: NOW,
      }),
    ).rejects.toThrow();
  });
});
