import { createHmac, timingSafeEqual } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  CashfreeMode,
  cashfreeApiBase,
  type CashfreeConfig,
} from './cashfree.config';

export type CreatedOrder = {
  /// What the app hands to Cashfree's SDK to open checkout. Null in stub mode, where there is no
  /// checkout to open.
  paymentSessionId: string | null;
};

export type OrderRequest = {
  orderId: string;
  amountPaise: bigint;
  customerId: number;
  phone: string;
  returnUrl: string | null;
};

/// The version of Cashfree's PG API this code is written against. Pinned, because their response
/// shape is versioned by this header and an unpinned integration breaks on their release schedule.
const API_VERSION = '2023-08-01';

/**
 * Cashfree Payment Gateway.
 *
 * Two jobs, and the second one is the one that matters: create an order, and prove that a webhook
 * claiming it was paid actually came from Cashfree. A webhook endpoint without signature
 * verification is an endpoint where anyone who knows an order id can grant themselves PRO.
 */
@Injectable()
export class CashfreeClient {
  private readonly log = new Logger(CashfreeClient.name);

  constructor(private readonly config: ConfigService) {}

  get mode(): CashfreeMode {
    return this.settings.mode;
  }

  /**
   * Rupees, as Cashfree's API wants them, from the paise we store.
   *
   * The ONLY place the two units meet. Prices are integer paise everywhere else (rule 3), and this
   * divides exactly because every price in the matrix is a whole number of paise.
   */
  static toRupees(amountPaise: bigint): number {
    return Number(amountPaise) / 100;
  }

  async createOrder(request: OrderRequest): Promise<CreatedOrder> {
    if (this.settings.mode === CashfreeMode.Stub) {
      // No call, no money, no session. The order row is still written, so everything downstream of
      // a real payment can be exercised through the simulate route.
      this.log.warn(
        `stub checkout for order ${request.orderId}: nothing was charged`,
      );
      return { paymentSessionId: null };
    }

    const { appId, secretKey } = this.requireCredentials();

    const response = await fetch(
      `${cashfreeApiBase(this.settings.mode)}/orders`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-version': API_VERSION,
          'x-client-id': appId,
          'x-client-secret': secretKey,
        },
        body: JSON.stringify({
          order_id: request.orderId,
          order_amount: CashfreeClient.toRupees(request.amountPaise),
          order_currency: 'INR',
          customer_details: {
            customer_id: String(request.customerId),
            customer_phone: request.phone,
          },
          ...(request.returnUrl
            ? { order_meta: { return_url: request.returnUrl } }
            : {}),
        }),
      },
    );

    if (!response.ok) {
      // The gateway's own message goes to the log and nowhere near the user (rule 5, rule 7): it
      // names amounts and ids, and the caller turns this into approved copy.
      const detail = await response.text().catch(() => '');
      this.log.error(
        `Cashfree refused order ${request.orderId}: ${response.status} ${detail}`,
      );
      throw new Error('CASHFREE_ORDER_FAILED');
    }

    const body = (await response.json()) as { payment_session_id?: string };
    return { paymentSessionId: body.payment_session_id ?? null };
  }

  /**
   * docs/11 §9's refund, at the gateway.
   *
   * Stub mode books nothing and says so: the rest of the refund — the order row, the subscription,
   * the reversed commission — still runs, so the whole path is exercisable before credentials exist.
   */
  async refund(request: {
    orderId: string;
    refundId: string;
    amountPaise: bigint;
  }): Promise<void> {
    if (this.settings.mode === CashfreeMode.Stub) {
      this.log.warn(
        `stub refund for order ${request.orderId}: no money moved at the gateway`,
      );
      return;
    }

    const { appId, secretKey } = this.requireCredentials();

    const response = await fetch(
      `${cashfreeApiBase(this.settings.mode)}/orders/${request.orderId}/refunds`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-version': API_VERSION,
          'x-client-id': appId,
          'x-client-secret': secretKey,
        },
        body: JSON.stringify({
          refund_id: request.refundId,
          refund_amount: CashfreeClient.toRupees(request.amountPaise),
          refund_note: 'Customer refund',
        }),
      },
    );

    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      this.log.error(
        `Cashfree refused refund for order ${request.orderId}: ${response.status} ${detail}`,
      );
      throw new Error('CASHFREE_REFUND_FAILED');
    }
  }

  /**
   * Whether this webhook really came from Cashfree.
   *
   * Their scheme is `base64(HMAC-SHA256(timestamp + rawBody, merchantSecretKey))` — the same
   * Client Secret that authenticates API calls. Cashfree has no separate webhook secret, so there
   * is nothing extra to create and nothing extra to get wrong (D-198).
   *
   * The RAW body, byte for byte: re-serialising the parsed JSON changes key order and whitespace
   * and the signature stops matching, which is the classic way this check gets quietly disabled.
   */
  verifyWebhook(
    rawBody: string,
    timestamp: string,
    signature: string,
  ): boolean {
    const secret = this.settings.secretKey;

    if (!secret) {
      // Refuse rather than accept. An unverifiable webhook is not a trusted one.
      this.log.error('CASHFREE_SECRET_KEY is not set; refusing every webhook');
      return false;
    }

    const expected = createHmac('sha256', secret)
      .update(timestamp + rawBody)
      .digest('base64');

    const given = Buffer.from(signature);
    const mine = Buffer.from(expected);

    // Length has to match before `timingSafeEqual`, which throws on a mismatch rather than
    // returning false.
    return given.length === mine.length && timingSafeEqual(given, mine);
  }

  private requireCredentials(): { appId: string; secretKey: string } {
    const { appId, secretKey } = this.settings;

    if (!appId || !secretKey) {
      throw new Error('CASHFREE_CREDENTIALS_MISSING');
    }

    return { appId, secretKey };
  }

  private get settings(): CashfreeConfig {
    return this.config.getOrThrow<CashfreeConfig>('cashfree');
  }
}
