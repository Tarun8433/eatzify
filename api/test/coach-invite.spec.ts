import { NotFoundException } from '@nestjs/common';
import { CoachInviteService } from '../src/coach/coach-invite.service';
import type { CoachInviteEntity } from '../src/coach/entities/coach-invite.entity';
import type { GrantScope } from '../src/coach/entities/coach-grant.entity';

/// docs/09 §6 and docs/10 §3. An invite is a REQUEST. It creates no access, and the only thing
/// that turns it into access is the client answering yes.

const NOW = new Date('2026-09-13T00:00:00Z');
const CLIENT_PHONE = '+919000000001';

type Granted = {
  clientUserId: number;
  coachUserId: number;
  scopes: readonly GrantScope[];
};

function serviceWith({
  existing = null as Partial<CoachInviteEntity> | null,
  capFails = false,
} = {}) {
  let row = existing as CoachInviteEntity | null;
  const granted: Granted[] = [];
  const updates: Record<string, unknown>[] = [];
  const promotionsAsked: number[] = [];

  const service = new CoachInviteService(
    {
      findOne: () => Promise.resolve(row),
      find: () => Promise.resolve(row ? [row] : []),
      save: (next: CoachInviteEntity) => {
        row = { ...row, ...next, id: row?.id ?? 'i1' } as CoachInviteEntity;
        return Promise.resolve(row);
      },
      update: (_id: unknown, patch: Record<string, unknown>) => {
        updates.push(patch);
        row = { ...row, ...patch } as CoachInviteEntity;
        return Promise.resolve({ affected: 1 });
      },
    } as never,
    // Users, profiles and applications: only the read paths touch them, and these tests are
    // about the ask itself.
    { find: () => Promise.resolve([]) } as never,
    { find: () => Promise.resolve([]) } as never,
    { find: () => Promise.resolve([]) } as never,
    {
      assertScopesWithinLevel: () => {
        if (capFails) throw new Error('SCOPE_ABOVE_COACH_LEVEL');
        return Promise.resolve();
      },
      grant: (args: Granted) => {
        granted.push(args);
        return Promise.resolve({});
      },
    } as never,
    {
      promoteToCoachingIfEligible: (coachUserId: number) => {
        promotionsAsked.push(coachUserId);
        return Promise.resolve(false);
      },
    } as never,
  );

  return { service, granted, updates, promotionsAsked, current: () => row };
}

const PENDING = {
  id: 'i1',
  coachUserId: 2,
  phoneE164: CLIENT_PHONE,
  scopes: ['basic', 'progress'] as GrantScope[],
  status: 'pending' as const,
  expiresAt: new Date('2026-10-01T00:00:00Z'),
  respondedAt: null,
};

/// Harness for `sentBy`, which is the only method that reads users and profiles.
function sentServiceWith({
  rows = [] as Partial<CoachInviteEntity>[],
  users = [] as Record<string, unknown>[],
  profiles = [] as Record<string, unknown>[],
  applications = [] as Record<string, unknown>[],
} = {}) {
  return new CoachInviteService(
    { find: () => Promise.resolve(rows) } as never,
    { find: () => Promise.resolve(users) } as never,
    { find: () => Promise.resolve(profiles) } as never,
    { find: () => Promise.resolve(applications) } as never,
    {} as never,
    {} as never,
  );
}

const SENT = {
  ...PENDING,
  createdAt: new Date('2026-09-12T00:00:00Z'),
};

async function notFound(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (e as NotFoundException).getResponse() as {
      error: { code: string };
    };
    return body.error.code;
  }
  throw new Error('expected the request to be refused');
}

describe('inviting is asking, not assigning', () => {
  /// The whole point. Creating an invite must not create access — only the client answering does.
  it('should create no grant when the coach sends an invite', async () => {
    const { service, granted } = serviceWith();

    await service.invite({
      coachUserId: 2,
      phoneE164: CLIENT_PHONE,
      scopes: ['basic'],
      now: NOW,
    });

    expect(granted).toEqual([]);
  });

  /// docs/09 §6: the same cap the grant is subject to, applied at the ASK — so a coach is told
  /// their level is too low when they invite, rather than leaving the client to hit it on accept.
  it('should refuse an invite for a scope above the coach level', async () => {
    const { service, current } = serviceWith({ capFails: true });

    await expect(
      service.invite({
        coachUserId: 2,
        phoneE164: CLIENT_PHONE,
        scopes: ['health_conditions'],
        now: NOW,
      }),
    ).rejects.toThrow();
    expect(current()).toBeNull();
  });

  /// A client's inbox must never show the same coach twice. Inviting again refreshes the live ask.
  it('should refresh the existing ask rather than stack a second one', async () => {
    const { service, current } = serviceWith({ existing: PENDING });

    await service.invite({
      coachUserId: 2,
      phoneE164: CLIENT_PHONE,
      scopes: ['basic'],
      now: NOW,
    });

    expect(current()?.id).toBe('i1');
    expect(current()?.scopes).toEqual(['basic']);
  });
});

describe('answering an invite', () => {
  it('should create the grant when the client accepts', async () => {
    const { service, granted, updates } = serviceWith({ existing: PENDING });

    await service.accept({
      inviteId: 'i1',
      clientUserId: 9,
      clientPhoneE164: CLIENT_PHONE,
      now: NOW,
    });

    expect(granted).toEqual([
      {
        clientUserId: 9,
        coachUserId: 2,
        scopes: ['basic', 'progress'],
        now: NOW,
      },
    ]);
    expect(updates[0]).toMatchObject({ status: 'accepted' });
  });

  it('should create nothing when the client declines', async () => {
    const { service, granted, updates } = serviceWith({ existing: PENDING });

    await service.decline({
      inviteId: 'i1',
      clientPhoneE164: CLIENT_PHONE,
      now: NOW,
    });

    expect(granted).toEqual([]);
    expect(updates[0]).toMatchObject({ status: 'declined' });
  });

  /// The id space must not become a way to learn who has been invited by whom, so an invite
  /// addressed to somebody else is simply not found.
  it('should refuse an invite addressed to a different number', async () => {
    const { service } = serviceWith({ existing: PENDING });

    const code = await notFound(
      service.accept({
        inviteId: 'i1',
        clientUserId: 9,
        clientPhoneE164: '+919999999999',
        now: NOW,
      }),
    );

    expect(code).toBe('INVITE_NOT_FOUND');
  });

  /// An unanswered invite is not a standing offer, and the expiry binds on READ rather than
  /// waiting for a sweep — the same rule grants follow.
  it('should refuse an invite that has lapsed, before any sweep has run', async () => {
    const { service, granted } = serviceWith({
      existing: { ...PENDING, expiresAt: new Date('2026-09-01T00:00:00Z') },
    });

    const code = await notFound(
      service.accept({
        inviteId: 'i1',
        clientUserId: 9,
        clientPhoneE164: CLIENT_PHONE,
        now: NOW,
      }),
    );

    expect(code).toBe('INVITE_NOT_FOUND');
    expect(granted).toEqual([]);
  });

  /// A "no" must not be answerable again into a "yes".
  it('should refuse an invite that has already been declined', async () => {
    const { service } = serviceWith({
      existing: { ...PENDING, status: 'declined' },
    });

    const code = await notFound(
      service.accept({
        inviteId: 'i1',
        clientUserId: 9,
        clientPhoneE164: CLIENT_PHONE,
        now: NOW,
      }),
    );

    expect(code).toBe('INVITE_NOT_FOUND');
  });
});

describe('the client inbox', () => {
  it('should list an open invite for this number', async () => {
    const { service } = serviceWith({ existing: PENDING });

    const rows = await service.pendingFor(CLIENT_PHONE, NOW);

    expect(rows).toHaveLength(1);
    expect(rows[0]?.coach_user_id).toBe(2);
  });

  it('should hide a lapsed invite even before the sweep', async () => {
    const { service } = serviceWith({
      existing: { ...PENDING, expiresAt: new Date('2026-09-01T00:00:00Z') },
    });

    expect(await service.pendingFor(CLIENT_PHONE, NOW)).toEqual([]);
  });
});

describe('the invites a coach has sent (their own Clients screen)', () => {
  it("should read back the coach's own pending asks", async () => {
    const service = sentServiceWith({ rows: [SENT] });

    const out = await service.sentBy(2, NOW);

    expect(out).toHaveLength(1);
    expect(out[0].phone_e164).toBe(CLIENT_PHONE);
    expect(out[0].scopes).toEqual(['basic', 'progress']);
    expect(out[0].status).toBe('pending');
  });

  /// An invite nobody can accept any more is not still pending — the same rule the client's
  /// inbox follows.
  it('should leave out an invite that has expired', async () => {
    const service = sentServiceWith({
      rows: [{ ...SENT, expiresAt: new Date('2026-09-01T00:00:00Z') }],
    });

    expect(await service.sentBy(2, NOW)).toEqual([]);
  });

  it('should carry the name and photo when the number belongs to an account', async () => {
    const service = sentServiceWith({
      rows: [SENT],
      users: [
        {
          id: 9,
          phone: CLIENT_PHONE,
          firstName: 'Asha',
          lastName: 'Rao',
          photo: { path: 'https://files.test/asha.jpg' },
        },
      ],
    });

    const out = await service.sentBy(2, NOW);

    expect(out[0].name).toBe('Asha Rao');
    expect(out[0].photo_url).toBe('https://files.test/asha.jpg');
  });

  /// A phone-OTP signup never fills `user.firstName`; onboarding puts the name on the profile.
  it('should fall back to the profile name', async () => {
    const service = sentServiceWith({
      rows: [SENT],
      users: [{ id: 9, phone: CLIENT_PHONE }],
      profiles: [{ userId: 9, name: 'Asha Rao' }],
    });

    expect((await service.sentBy(2, NOW))[0].name).toBe('Asha Rao');
  });

  /// The number is not on the app. Null rather than a placeholder — the screen says "invited" and
  /// nothing more, and a made-up name would be a claim about somebody who does not exist here.
  it('should return nulls when the number belongs to nobody', async () => {
    const service = sentServiceWith({ rows: [SENT] });

    const out = await service.sentBy(2, NOW);

    expect(out[0].name).toBeNull();
    expect(out[0].photo_url).toBeNull();
  });
});

describe('who is asking (the client must be able to decide)', () => {
  /// "Partner #25" is what this screen showed before. Consent that cannot name its recipient is
  /// not informed consent — and unlike the client's details, a coach APPLIED to be listed.
  it('should name the coach who sent the invite', async () => {
    const service = sentServiceWith({
      rows: [SENT],
      users: [{ id: 2, firstName: 'Neha', lastName: 'Singh' }],
      applications: [
        { userId: 2, discipline: 'nutritionist', status: 'verified' },
      ],
    });

    const out = await service.pendingFor(CLIENT_PHONE, NOW);

    expect(out[0].coach_name).toBe('Neha Singh');
    expect(out[0].coach_discipline).toBe('nutritionist');
    expect(out[0].coach_verified).toBe(true);
  });

  /// doc 00 §8: Eatzify is not an accrediting body. The claim is "we saw this document", and it
  /// travels with the words that say so (docs/12 §6).
  it('should publish what was actually checked, and what that means', async () => {
    const service = sentServiceWith({
      rows: [SENT],
      users: [{ id: 2, firstName: 'Neha' }],
      applications: [
        {
          userId: 2,
          status: 'verified',
          verifiedAttributes: ['identity', 'qualification_document'],
        },
      ],
    });

    const out = await service.pendingFor(CLIENT_PHONE, NOW);

    expect(out[0].coach_verified_attributes).toEqual([
      'identity',
      'qualification_document',
    ]);
    expect(out[0].what_verification_means.length).toBeGreaterThan(0);
  });

  /// An unreviewed applicant has confirmed nothing. Saying otherwise would be the app making an
  /// accreditation claim on their behalf.
  it('should claim nothing for an application nobody has reviewed', async () => {
    const service = sentServiceWith({
      rows: [SENT],
      users: [{ id: 2, firstName: 'Neha' }],
      applications: [
        {
          userId: 2,
          status: 'submitted',
          verifiedAttributes: ['identity'],
        },
      ],
    });

    const out = await service.pendingFor(CLIENT_PHONE, NOW);

    expect(out[0].coach_verified).toBe(false);
    expect(out[0].coach_verified_attributes).toEqual([]);
  });

  it('should leave out an invite that has expired', async () => {
    const service = sentServiceWith({
      rows: [{ ...SENT, expiresAt: new Date('2026-09-01T00:00:00Z') }],
    });

    expect(await service.pendingFor(CLIENT_PHONE, NOW)).toEqual([]);
  });
});

/// D-235: a client's yes is the third condition for level 3, so accepting asks whether the coach
/// has just become a Coaching Partner.
describe('what accepting does to the coach', () => {
  it('should ask whether the coach now qualifies for level 3', async () => {
    const { service, promotionsAsked } = serviceWith({
      existing: { ...PENDING },
    });

    await service.accept({
      inviteId: 'i1',
      clientUserId: 7,
      clientPhoneE164: CLIENT_PHONE,
      now: new Date('2026-09-18T00:00:00Z'),
    });

    expect(promotionsAsked).toEqual([2]);
  });
});
