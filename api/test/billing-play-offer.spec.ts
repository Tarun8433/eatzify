import { BillingService } from '../src/billing/billing.service';

/// Android is sent to Google Play only for plans Play is really selling. A plan missing or inactive
/// in Play Console used to become a Pay button that could not open ("Payments cannot be opened on
/// this build yet").
function service(live: string[]) {
  return new BillingService(
    { findOne: () => Promise.resolve(null) } as never,
    { mode: 'production', androidEnabled: false } as never,
    {} as never,
    {
      configured: true,
      liveBasePlans: () => Promise.resolve(new Set(live)),
    } as never,
    { configured: false } as never,
  );
}

describe('Play offer on Android', () => {
  it('should offer only the plans live in Play', async () => {
    const view = await service(['basic:p1m', 'pro:p1y']).entitlements(
      1,
      'android',
    );
    expect(view.payments_mode).toBe('play');
    expect(
      view.play_products?.map((p) => `${p.product_id}:${p.base_plan_id}`),
    ).toEqual(['basic:p1m', 'pro:p1y']);
  });

  it('should draw no Pay button when Play sells nothing yet', async () => {
    const view = await service([]).entitlements(1, 'android');
    expect(view.payments_mode).toBe('unavailable');
    expect(view.play_products).toBeUndefined();
  });
});
