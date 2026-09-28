import type { Repository } from 'typeorm';
import { CouponsService } from '../src/billing/coupons.service';
import type { CouponEntity } from '../src/billing/entities/coupon.entity';

/// D-236. The rules an offer lives by, against an in-memory repo.
function repo(rows: Partial<CouponEntity>[] = []) {
  const store = rows.map((r) => ({
    usedCount: 0,
    active: true,
    expiresAt: null,
    ...r,
  }));
  return {
    store,
    findOne: ({ where }: { where: { code: string } }) =>
      Promise.resolve(store.find((r) => r.code === where.code) ?? null),
    find: () => Promise.resolve([...store]),
    create: (r: Partial<CouponEntity>) => ({ createdAt: new Date(), ...r }),
    save: (r: CouponEntity) => {
      const at = store.findIndex((x) => x.code === r.code);
      if (at >= 0) store[at] = r;
      else store.push(r);
      return Promise.resolve(r);
    },
    increment: (where: { code: string }, _f: string, by: number) => {
      const row = store.find((r) => r.code === where.code);
      if (row) row.usedCount = (row.usedCount ?? 0) + by;
      return Promise.resolve();
    },
  } as unknown as Repository<CouponEntity> & { store: Partial<CouponEntity>[] };
}

const NOW = new Date('2026-09-18T10:00:00Z');

describe('coupons (D-236)', () => {
  it('prices a valid code in integer paise, floored', async () => {
    const s = new CouponsService(
      repo([{ code: 'DIWALI33', percentOff: 33, maxUses: 10 }]),
    );
    const offer = await s.discountFor(' diwali33 ', 64_900n, NOW);
    // 33 % of 64,900 = 21,417 exactly; bigint math never sees a float.
    expect(offer).toEqual({ code: 'DIWALI33', discountPaise: 21_417n });
  });

  it('answers null for unknown, inactive, expired and exhausted alike', async () => {
    const s = new CouponsService(
      repo([
        { code: 'OFF', percentOff: 10, maxUses: 5, active: false },
        {
          code: 'OLD',
          percentOff: 10,
          maxUses: 5,
          expiresAt: new Date('2026-01-01'),
        },
        { code: 'DONE', percentOff: 10, maxUses: 2, usedCount: 2 },
      ]),
    );
    for (const code of ['NOPE', 'OFF', 'OLD', 'DONE']) {
      expect(await s.discountFor(code, 10_000n, NOW)).toBeNull();
    }
  });

  it('refuses a discount above 90 % at creation — no zero-amount orders, ever', async () => {
    const s = new CouponsService(repo());
    await expect(
      s.create({ code: 'FREE100', percent_off: 100, max_uses: 1 }),
    ).rejects.toMatchObject({ status: 422 });
  });

  it('refuses a malformed code and a duplicate', async () => {
    const s = new CouponsService(
      repo([{ code: 'TAKEN', percentOff: 5, maxUses: 1 }]),
    );
    await expect(
      s.create({ code: 'x', percent_off: 10, max_uses: 1 }),
    ).rejects.toMatchObject({
      status: 422,
    });
    await expect(
      s.create({ code: 'taken', percent_off: 10, max_uses: 1 }),
    ).rejects.toMatchObject({
      status: 422,
    });
  });

  it('deactivation keeps the row and its usage visible', async () => {
    const r = repo([{ code: 'RUN', percentOff: 10, maxUses: 5, usedCount: 3 }]);
    const s = new CouponsService(r);
    const view = await s.deactivate('run');
    expect(view.active).toBe(false);
    expect(view.used_count).toBe(3);
    expect(r.store).toHaveLength(1);
  });

  it('redeem counts one use', async () => {
    const r = repo([{ code: 'RUN', percentOff: 10, maxUses: 5 }]);
    const s = new CouponsService(r);
    await s.redeem('run');
    expect(r.store[0]!.usedCount).toBe(1);
  });
});
