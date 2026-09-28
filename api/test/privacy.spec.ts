import { type DataSource, type Repository } from 'typeorm';
import { PrivacyService } from '../src/privacy/privacy.service';
import { PrivacySweepService } from '../src/privacy/privacy-sweep.service';
import { PrivacyRequestEntity } from '../src/privacy/entities/privacy-request.entity';
import { ConsentEntity } from '../src/profile/entities/consent.entity';
import { UserEntity } from '../src/users/infrastructure/persistence/relational/entities/user.entity';
import { NotificationsService } from '../src/notifications/notifications.service';
import { addDays, addHours } from '../src/privacy/privacy-rules';

/// docs/13 §3 (consent, withdrawable) and §9 (access and erasure, "as features, not tickets").

const NOW = new Date('2026-09-18T10:00:00Z');
const USER = 7;

type Request = Partial<PrivacyRequestEntity>;
type Consent = Partial<ConsentEntity>;

function serviceWith({
  requests = [],
  consents = [],
}: { requests?: Request[]; consents?: Consent[] } = {}) {
  const sent: { kind: string; userId: number }[] = [];
  const deleted: string[] = [];
  const updated: Record<string, unknown>[] = [];

  const requestRepo = {
    create: (row: Request) => row,
    save: (row: Request) => {
      const at = requests.findIndex((r) => r.id && r.id === row.id);
      const saved = {
        id: row.id ?? `r${requests.length + 1}`,
        createdAt: row.createdAt ?? NOW,
        ...row,
      };
      if (at >= 0) requests[at] = saved;
      else requests.push(saved);
      return Promise.resolve(saved);
    },
    find: ({ where }: { where?: Record<string, unknown> } = {}) =>
      Promise.resolve(
        requests.filter((r) => {
          const w = where ?? {};
          if (w.userId !== undefined && r.userId !== w.userId) return false;
          if (w.kind !== undefined && r.kind !== w.kind) return false;
          const status = w.status as { _value?: string[] } | string | undefined;
          if (typeof status === 'string' && r.status !== status) return false;
          if (status && typeof status === 'object' && status._value) {
            if (!status._value.includes(r.status as string)) return false;
          }
          return true;
        }),
      ),
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(
        requests.find(
          (r) =>
            (where.id === undefined || r.id === where.id) &&
            (where.userId === undefined || r.userId === where.userId) &&
            (where.kind === undefined || r.kind === where.kind),
        ) ?? null,
      ),
  } as unknown as Repository<PrivacyRequestEntity>;

  const consentRepo = {
    create: (row: Consent) => row,
    save: (row: Consent) => {
      consents.push({ grantedAt: NOW, ...row });
      return Promise.resolve(row);
    },
    find: () => Promise.resolve(consents),
  } as unknown as Repository<ConsentEntity>;

  const userRepo = {
    findOne: () =>
      Promise.resolve({
        id: USER,
        email: 'someone@example.test',
        phone: null,
        firstName: 'A',
        lastName: 'B',
        createdAt: NOW,
      }),
  } as unknown as Repository<UserEntity>;

  const notifications = {
    notify: (input: { kind: string; userId: number }) => {
      sent.push({ kind: input.kind, userId: input.userId });
      return Promise.resolve(null);
    },
  } as unknown as NotificationsService;

  const dataSource = {
    getRepository: () => ({
      find: () => Promise.resolve([{ id: 1 }, { id: 2 }]),
      delete: (where: Record<string, unknown>) => {
        deleted.push(JSON.stringify(where));
        return Promise.resolve({ affected: 2 });
      },
      update: (_: unknown, patch: Record<string, unknown>) => {
        updated.push(patch);
        return Promise.resolve({ affected: 1 });
      },
      softDelete: () => Promise.resolve({ affected: 1 }),
    }),
    transaction: (run: (tx: unknown) => Promise<void>) =>
      run({
        getRepository: () => ({
          delete: (where: Record<string, unknown>) => {
            deleted.push(JSON.stringify(where));
            return Promise.resolve({ affected: 2 });
          },
          update: (_: unknown, patch: Record<string, unknown>) => {
            updated.push(patch);
            return Promise.resolve({ affected: 1 });
          },
          softDelete: () => Promise.resolve({ affected: 1 }),
        }),
      }),
  } as unknown as DataSource;

  const service = new PrivacyService(
    requestRepo,
    consentRepo,
    userRepo,
    notifications,
    dataSource,
  );

  return {
    service,
    sweep: new PrivacySweepService(requestRepo, service, notifications),
    requests,
    consents,
    sent,
    deleted,
    updated,
  };
}

async function refusedCode(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (
      e as { getResponse(): { error?: { code: string } } }
    ).getResponse();
    return body.error?.code ?? 'NO_CODE';
  }
  throw new Error('expected the call to be refused');
}

describe('consent, and taking it back (docs/13 §3)', () => {
  it('should default marketing to off, with nothing pre-ticked', async () => {
    const { service } = serviceWith();

    const rows = await service.consents(USER);

    expect(rows.find((r) => r.type === 'marketing')).toMatchObject({
      granted: false,
      decided_at: null,
    });
  });

  /// Append-only: the row that says "yes" stays, so what they agreed to when a field was stored is
  /// still answerable.
  it('should record a withdrawal as a new row, never an update', async () => {
    const { service, consents } = serviceWith();

    await service.setConsent(USER, 'marketing', true);
    const after = await service.setConsent(USER, 'marketing', false);

    expect(consents).toHaveLength(2);
    expect(consents.map((c) => c.granted)).toEqual([true, false]);
    expect(after.find((r) => r.type === 'marketing')?.granted).toBe(false);
  });

  it('should keep the notice version the person actually agreed to', async () => {
    const { service, consents } = serviceWith();

    await service.setConsent(USER, 'health_data_storage', true, '2.1.0');

    expect(consents[0]).toMatchObject({ policyVersion: '2.1.0' });
  });

  /// docs/13 §3: withdrawing health processing stops plan generation.
  it('should say when health processing may no longer happen', async () => {
    const { service } = serviceWith();

    await service.setConsent(USER, 'health_data_storage', true);
    expect(await service.mayProcessHealth(USER)).toBe(true);

    await service.setConsent(USER, 'health_data_storage', false);
    expect(await service.mayProcessHealth(USER)).toBe(false);
  });
});

describe('export (docs/13 §9)', () => {
  it('should build the bundle and expire the link a day later', async () => {
    const { service } = serviceWith();

    const view = await service.requestExport(USER, NOW);

    expect(view).toMatchObject({ kind: 'export', status: 'done' });
    expect(view.download_expires_at).toBe(addHours(NOW, 24).toISOString());
  });

  it('should hand back the data while the link is alive', async () => {
    const { service, requests } = serviceWith();
    await service.requestExport(USER, NOW);

    const bundle = await service.bundleFor(USER, requests[0].id!, NOW);

    expect(bundle.account).toMatchObject({ user_id: USER });
    expect(bundle.food_logs).toHaveLength(2);
  });

  it('should refuse the link once it has expired', async () => {
    const { service, requests } = serviceWith();
    await service.requestExport(USER, NOW);

    expect(
      await refusedCode(
        service.bundleFor(USER, requests[0].id!, addHours(NOW, 25)),
      ),
    ).toBe('EXPORT_EXPIRED');
  });

  it('should not hand somebody else their export', async () => {
    const { service, requests } = serviceWith();
    await service.requestExport(USER, NOW);

    expect(await refusedCode(service.bundleFor(8, requests[0].id!, NOW))).toBe(
      'EXPORT_NOT_FOUND',
    );
  });
});

describe('erasure, from asked to done (docs/13 §9)', () => {
  it('should wait seven days and say so', async () => {
    const { service, sent } = serviceWith();

    const view = await service.requestDelete(USER, NOW);

    expect(view.execute_after).toBe(addDays(NOW, 7).toISOString());
    expect(sent).toEqual([
      { kind: 'account_deletion_requested', userId: USER },
    ]);
  });

  it('should treat asking twice as one intention', async () => {
    const { service } = serviceWith();
    await service.requestDelete(USER, NOW);

    expect(await refusedCode(service.requestDelete(USER, NOW))).toBe(
      'DELETE_ALREADY_REQUESTED',
    );
  });

  it('should stop when the person changes their mind', async () => {
    const { service, requests, sent } = serviceWith();
    await service.requestDelete(USER, NOW);

    await service.cancelDelete(USER, addDays(NOW, 1));

    expect(requests[0].status).toBe('cancelled');
    expect(sent.map((s) => s.kind)).toContain('account_deletion_cancelled');
  });

  it('should say when there is nothing to stop', async () => {
    const { service } = serviceWith();

    expect(await refusedCode(service.cancelDelete(USER, NOW))).toBe(
      'NO_DELETE_PENDING',
    );
  });

  /**
   * docs/13 §6: a real delete of the health rows and a tombstone where the person was — never a
   * flag on everything. The account row survives because an invoice has to keep pointing at it.
   */
  it('should delete the health rows and tombstone the account', async () => {
    const { service, deleted, updated } = serviceWith();

    const counts = await service.erase(USER, NOW);

    // Five health tables plus the four gym ones (ADR-013).
    expect(deleted).toHaveLength(9);
    expect(counts.food_logs).toBe(2);
    expect(Object.keys(counts)).toEqual(
      expect.arrayContaining([
        'gym_workouts',
        'gym_routines',
        'gym_profile',
        'gym_custom_exercises',
      ]),
    );
    expect(counts.user_tombstoned).toBe(1);
    expect(updated[0]).toMatchObject({
      email: null,
      phone: null,
      firstName: null,
      lastName: null,
    });
  });
});

describe('the nightly sweep', () => {
  it('should warn 48 hours ahead rather than erase', async () => {
    const { sweep, requests, sent } = serviceWith({
      requests: [
        {
          id: 'r1',
          userId: USER,
          kind: 'delete',
          status: 'pending',
          executeAfter: addDays(NOW, 7),
          notifiedAt: null,
          createdAt: NOW,
        },
      ],
    });

    const report = await sweep.run(addHours(addDays(NOW, 7), -47));

    expect(report).toEqual({ notified: 1, erased: 0 });
    expect(requests[0].status).toBe('notified');
    expect(sent.map((s) => s.kind)).toContain('account_deletion_imminent');
  });

  /// A person warned two hours before deletion was not warned.
  it('should not erase until 48 hours after the warning went out', async () => {
    const due = addDays(NOW, 7);
    const { sweep } = serviceWith({
      requests: [
        {
          id: 'r1',
          userId: USER,
          kind: 'delete',
          status: 'notified',
          executeAfter: due,
          notifiedAt: addHours(due, -2),
          createdAt: NOW,
        },
      ],
    });

    expect(await sweep.run(due)).toEqual({ notified: 0, erased: 0 });
    expect(await sweep.run(addHours(due, 47))).toEqual({
      notified: 0,
      erased: 1,
    });
  });

  it('should leave a cancelled request alone forever', async () => {
    const { sweep } = serviceWith({
      requests: [
        {
          id: 'r1',
          userId: USER,
          kind: 'delete',
          status: 'cancelled',
          executeAfter: addDays(NOW, -30),
          notifiedAt: addDays(NOW, -32),
          createdAt: addDays(NOW, -37),
        },
      ],
    });

    expect(await sweep.run(NOW)).toEqual({ notified: 0, erased: 0 });
  });
});
