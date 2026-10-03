import { RefundService } from '../src/billing/refund.service';
import { RefundRequestService } from '../src/billing/refund-request.service';
import { AdminPaymentsController } from '../src/admin/admin-payments.controller';
import { RoleEnum } from '../src/roles/roles.enum';

/// Admin panel plan, Phase B: refunds past the 7-day window go through a person in finance, and
/// every refund an admin makes runs the same path as self-serve (gateway first).

const DAY = 86_400_000;
const NOW = new Date('2026-10-20T10:00:00Z');

type Order = {
  id: string;
  cashfreeOrderId: string;
  userId: number;
  status: string;
  paidAt: Date | null;
  amountPaise: string;
  tier: string;
  duration: string;
  refundedAt?: Date | null;
};

function setup(paidDaysAgo: number) {
  const order: Order = {
    id: 'o-uuid',
    cashfreeOrderId: 'eatzify_1',
    userId: 5,
    status: 'paid',
    paidAt: new Date(NOW.getTime() - paidDaysAgo * DAY),
    amountPaise: '64900',
    tier: 'PRO',
    duration: '1M',
  };
  const gateway: string[] = [];
  const notices: { kind: string; body: string }[] = [];
  const rows: Record<string, unknown>[] = [];

  const orderRepo = {
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(
        Object.entries(where).every(([k, v]) => order[k as keyof Order] === v)
          ? order
          : null,
      ),
    findOneOrFail: () => Promise.resolve(order),
    find: () => Promise.resolve([order]),
    save: (o: Order) => Promise.resolve(o),
  };
  const notifications = {
    notify: (n: { kind: string; body: string }) => (
      notices.push(n),
      Promise.resolve()
    ),
  };
  const refunds = new RefundService(
    orderRepo as never,
    {
      findOne: () => Promise.resolve(null),
      save: (s: unknown) => Promise.resolve(s),
    } as never,
    {
      refund: ({ orderId }: { orderId: string }) => (
        gateway.push(orderId),
        Promise.resolve()
      ),
    } as never,
    { reverseForOrder: () => Promise.resolve() } as never,
    notifications as never,
  );
  const requestRepo = {
    findOne: ({ where }: { where: Record<string, unknown> }) =>
      Promise.resolve(
        rows.find((r) => Object.entries(where).every(([k, v]) => r[k] === v)) ??
          null,
      ),
    find: ({ where }: { where?: Record<string, unknown> } = {}) =>
      Promise.resolve(
        rows.filter((r) =>
          Object.entries(where ?? {}).every(([k, v]) => r[k] === v),
        ),
      ),
    create: (r: Record<string, unknown>) => ({
      status: 'requested',
      createdAt: NOW,
      ...r,
    }),
    save: (r: Record<string, unknown>) => {
      if (!r.id) {
        r.id = `rq-${rows.length + 1}`;
        rows.push(r);
      }
      return Promise.resolve(r);
    },
  };
  const requests = new RefundRequestService(
    requestRepo as never,
    orderRepo as never,
    refunds,
    notifications as never,
  );
  return { order, gateway, notices, rows, refunds, requests };
}

describe('refund requests', () => {
  it('should send someone still inside 7 days to self-serve', async () => {
    const { requests } = setup(3);
    await expect(
      requests.request(5, 'eatzify_1', 'changed my mind', NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'REFUND_USE_SELF_SERVE' } },
    });
  });

  it("should refuse someone else's order and a second open request", async () => {
    const { requests } = setup(20);
    await expect(
      requests.request(6, 'eatzify_1', 'not mine', NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'REFUND_NOT_AVAILABLE' } },
    });
    await requests.request(5, 'eatzify_1', 'charged twice', NOW);
    await expect(
      requests.request(5, 'eatzify_1', 'again', NOW),
    ).rejects.toMatchObject({
      status: 409,
    });
  });

  it('should refund through the gateway on approval, past the window', async () => {
    const { requests, gateway, order } = setup(20);
    const asked = await requests.request(5, 'eatzify_1', 'charged twice', NOW);

    const { request, refund } = await requests.approve(asked.id, 1, NOW);

    expect(gateway).toEqual(['eatzify_1']);
    expect(order.status).toBe('refunded');
    expect(refund.refunded_paise).toBe('64900');
    expect(request).toMatchObject({ status: 'approved', decided_by: 1 });
    await expect(requests.approve(asked.id, 1, NOW)).rejects.toMatchObject({
      status: 409,
    });
  });

  it('should tell the person why on rejection, and move no money', async () => {
    const { requests, gateway, notices } = setup(20);
    const asked = await requests.request(
      5,
      'eatzify_1',
      'did not like it',
      NOW,
    );

    const decided = await requests.reject(
      asked.id,
      'The plan was used for 3 weeks.',
      1,
      NOW,
    );

    expect(decided.status).toBe('rejected');
    expect(gateway).toEqual([]);
    expect(notices).toEqual([
      expect.objectContaining({
        kind: 'refund_rejected',
        body: 'The plan was used for 3 weeks.',
      }),
    ]);
  });

  it('should keep the 7-day window on self-serve', async () => {
    const { refunds } = setup(20);
    await expect(
      refunds.refund(5, 'eatzify_1', null, NOW),
    ).rejects.toMatchObject({
      response: { error: { code: 'REFUND_WINDOW_CLOSED' } },
    });
  });
});

describe('the payments list in the app', () => {
  it('should offer self-serve inside 7 days, a request after, and nothing once refunded', async () => {
    const recent = setup(3);
    expect((await recent.requests.paidOrdersFor(5, NOW))[0].refund).toBe(
      'self_serve',
    );

    const old = setup(20);
    expect((await old.requests.paidOrdersFor(5, NOW))[0].refund).toBe(
      'request',
    );
    await old.requests.request(5, 'eatzify_1', 'charged twice', NOW);
    expect((await old.requests.paidOrdersFor(5, NOW))[0].refund).toBe(
      'requested',
    );

    old.order.status = 'refunded';
    expect((await old.requests.paidOrdersFor(5, NOW))[0]).toMatchObject({
      status: 'refunded',
      refund: null,
    });
  });
});

describe('AdminPaymentsController refund', () => {
  it('should ask for the authenticator before any money moves, then audit it', async () => {
    const { refunds, gateway } = setup(20);
    const audits: Record<string, unknown>[] = [];
    let totpChecked = false;
    const controller = new AdminPaymentsController(
      {} as never,
      refunds,
      {} as never,
      {
        require: (_id: number, code: string) => {
          totpChecked = true;
          return code === '123456'
            ? Promise.resolve()
            : Promise.reject(new Error('bad code'));
        },
      } as never,
      {
        record: (r: Record<string, unknown>) => (
          audits.push(r),
          Promise.resolve()
        ),
      } as never,
    );
    const request = {
      user: { id: 1, role: { id: RoleEnum.finance } },
    } as never;

    await expect(
      controller.refund(
        'eatzify_1',
        { reason: 'duplicate charge' },
        '000000',
        request,
        '1.1.1.1',
      ),
    ).rejects.toThrow('bad code');
    expect(gateway).toEqual([]);

    await controller.refund(
      'eatzify_1',
      { reason: 'duplicate charge' },
      '123456',
      request,
      '1.1.1.1',
    );
    expect(totpChecked).toBe(true);
    expect(gateway).toEqual(['eatzify_1']);
    expect(audits).toEqual([
      expect.objectContaining({
        action: 'refund_admin',
        meta: expect.objectContaining({ reason: 'duplicate charge' }),
      }),
    ]);
  });
});
