import { createHmac } from 'node:crypto';
import { CashfreeClient } from '../src/billing/cashfree.client';
import { CashfreeMode } from '../src/billing/cashfree.config';

/// The webhook route carries no bearer token — the caller is a gateway, not a person. The
/// signature is what stands in for one, so anyone who can forge it can grant themselves PRO.
///
/// The key is the merchant's Client Secret. Cashfree has no separate webhook secret (D-198).

const SECRET = 'test_webhook_secret';
const TIMESTAMP = '1757000000';
const BODY =
  '{"type":"PAYMENT_SUCCESS_WEBHOOK","data":{"order":{"order_id":"eatzify_1"}}}';

function sign(body: string, timestamp = TIMESTAMP, secret = SECRET): string {
  return createHmac('sha256', secret)
    .update(timestamp + body)
    .digest('base64');
}

function clientWith(secret: string | null, mode = CashfreeMode.Sandbox) {
  return new CashfreeClient({
    getOrThrow: () => ({
      mode,
      appId: 'app',
      secretKey: secret,
      returnUrl: null,
    }),
  } as never);
}

describe('proving a webhook came from Cashfree', () => {
  it('should accept a body signed with the shared secret', () => {
    const client = clientWith(SECRET);

    expect(client.verifyWebhook(BODY, TIMESTAMP, sign(BODY))).toBe(true);
  });

  /// The whole point. A forged success is a free subscription.
  it('should refuse a body signed with the wrong secret', () => {
    const client = clientWith(SECRET);

    const forged = sign(BODY, TIMESTAMP, 'not_the_secret');

    expect(client.verifyWebhook(BODY, TIMESTAMP, forged)).toBe(false);
  });

  /// The signature covers the body, so editing which order was paid must invalidate it.
  it('should refuse a body that was edited after signing', () => {
    const client = clientWith(SECRET);
    const signature = sign(BODY);

    const tampered = BODY.replace('eatzify_1', 'eatzify_2');

    expect(client.verifyWebhook(tampered, TIMESTAMP, signature)).toBe(false);
  });

  /// The timestamp is part of the signed material, so a captured webhook cannot be re-dated.
  it('should refuse a signature replayed under a different timestamp', () => {
    const client = clientWith(SECRET);
    const signature = sign(BODY);

    expect(client.verifyWebhook(BODY, '1757009999', signature)).toBe(false);
  });

  /// The same key that authenticates an API call. A test that used a different one would pass
  /// while the real integration refused every webhook — which is the bug D-198 fixed.
  it('should verify with the key that also authenticates API calls', () => {
    const client = clientWith(SECRET);
    const signedWithClientSecret = createHmac('sha256', SECRET)
      .update(TIMESTAMP + BODY)
      .digest('base64');

    expect(client.verifyWebhook(BODY, TIMESTAMP, signedWithClientSecret)).toBe(
      true,
    );
  });

  /// Refuse, never wave through. An unconfigured secret means every webhook is unverifiable, and
  /// an unverifiable payment notification is not a payment.
  it('should refuse everything when no secret is configured', () => {
    const client = clientWith(null);

    expect(client.verifyWebhook(BODY, TIMESTAMP, sign(BODY))).toBe(false);
  });

  /// `timingSafeEqual` throws on a length mismatch rather than returning false, so a short
  /// signature has to be caught before it reaches the comparison.
  it('should refuse a signature of the wrong length without throwing', () => {
    const client = clientWith(SECRET);

    expect(client.verifyWebhook(BODY, TIMESTAMP, 'short')).toBe(false);
    expect(client.verifyWebhook(BODY, TIMESTAMP, '')).toBe(false);
  });
});

describe('paise to rupees', () => {
  /// The single place the two units meet. `api/CLAUDE.md` rule 3 keeps money as integer paise
  /// everywhere else; Cashfree's API wants decimal rupees.
  it('should convert without a floating-point surprise', () => {
    expect(CashfreeClient.toRupees(BigInt(499_900))).toBe(4999);
    expect(CashfreeClient.toRupees(BigInt(24_900))).toBe(249);
    expect(CashfreeClient.toRupees(BigInt(179_900))).toBe(1799);
  });
});

describe('stub mode', () => {
  it('should charge nothing and open no session', async () => {
    const client = clientWith(SECRET, CashfreeMode.Stub);

    const order = await client.createOrder({
      orderId: 'eatzify_1',
      amountPaise: BigInt(499_900),
      customerId: 1,
      phone: '+919000000001',
      returnUrl: null,
    });

    expect(order.paymentSessionId).toBeNull();
  });
});
