import { PriceService } from '../src/billing/price.service';
import { PRICES } from '../src/billing/tiers';

type Row = { tier: string; duration: string; pricePaise: string };

function serviceWith(rows: Row[]) {
  const table = { rows, reads: 0 };
  const service = new PriceService({
    find: () => {
      table.reads++;
      return Promise.resolve(table.rows);
    },
  } as never);
  return { service, table };
}

describe('PriceService (payments plan, Phase 3)', () => {
  it('should charge what the admin set, as a number of paise', async () => {
    const { service } = serviceWith([
      { tier: 'PRO', duration: '3M', pricePaise: '149900' },
    ]);
    expect(await service.priceOf('PRO', '3M')).toBe(149_900);
  });

  it('should fall back to the shipped price for a missing cell', async () => {
    const { service } = serviceWith([]);
    expect(await service.priceOf('BASIC', '12M')).toBe(PRICES.BASIC['12M']);
  });

  it('should know nothing about FREE, 9M or a stray row', async () => {
    const { service } = serviceWith([
      { tier: 'GOLD', duration: '1M', pricePaise: '100' },
      { tier: 'PRO', duration: '9M', pricePaise: '100' },
    ]);
    expect(await service.priceOf('FREE', '1M')).toBeUndefined();
    expect(await service.priceOf('PRO', '9M')).toBeUndefined();
    expect(Object.keys(await service.matrix())).toEqual(['BASIC', 'PRO']);
  });

  it('should pick up an admin change once the cache has aged out', async () => {
    const { service, table } = serviceWith([
      { tier: 'PRO', duration: '1M', pricePaise: '64900' },
    ]);
    await service.matrix(0);
    table.rows = [{ tier: 'PRO', duration: '1M', pricePaise: '59900' }];

    expect((await service.matrix(30_000)).PRO['1M']).toBe(64_900);
    expect((await service.matrix(61_000)).PRO['1M']).toBe(59_900);
    expect(table.reads).toBe(2);
  });

  it('should never change the shipped defaults', async () => {
    const { service } = serviceWith([
      { tier: 'PRO', duration: '1M', pricePaise: '100' },
    ]);
    await service.matrix();
    expect(PRICES.PRO['1M']).toBe(64_900);
  });
});
