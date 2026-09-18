import {
  Controller,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  RawBodyRequest,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Request } from 'express';
import { CashfreeClient } from './cashfree.client';
import { CheckoutService } from './checkout.service';

/// Cashfree's success and failure events. Anything else is acknowledged and ignored — a gateway
/// adds event types over time and a 500 on an unknown one makes them retry it forever.
const PAID = 'PAYMENT_SUCCESS_WEBHOOK';
const FAILED = 'PAYMENT_FAILED_WEBHOOK';

type WebhookBody = {
  type?: string;
  data?: {
    order?: { order_id?: string };
    payment?: { payment_status?: string; payment_message?: string };
  };
};

/**
 * Where Cashfree tells us a payment happened.
 *
 * Its own controller because it is the one route here that carries no bearer token — the caller is
 * a gateway, not a person. What replaces the token is the signature, and nothing in this file runs
 * before that check passes.
 */
@ApiExcludeController()
@Controller({ path: 'billing/webhook', version: '1' })
export class CashfreeWebhookController {
  constructor(
    private readonly cashfree: CashfreeClient,
    private readonly checkout: CheckoutService,
  ) {}

  @Post('cashfree')
  @HttpCode(HttpStatus.OK)
  async receive(
    @Req() request: RawBodyRequest<Request>,
    @Headers('x-webhook-signature') signature?: string,
    @Headers('x-webhook-timestamp') timestamp?: string,
  ): Promise<{ received: true }> {
    // The RAW bytes. Re-serialising the parsed body changes key order and whitespace, and the
    // signature stops matching — which is how this check gets quietly disabled.
    const raw = request.rawBody?.toString('utf8');

    if (!raw || !signature || !timestamp) {
      throw new UnauthorizedException('Unsigned webhook.');
    }

    if (!this.cashfree.verifyWebhook(raw, timestamp, signature)) {
      throw new UnauthorizedException('Bad webhook signature.');
    }

    const body = JSON.parse(raw) as WebhookBody;
    const orderId = body.data?.order?.order_id;
    if (!orderId) return { received: true };

    const now = new Date();

    if (body.type === PAID) {
      await this.checkout.markPaid(orderId, now);
    } else if (body.type === FAILED) {
      await this.checkout.markFailed(
        orderId,
        body.data?.payment?.payment_message ?? 'declined',
        now,
      );
    }

    // 200 for everything that got past the signature, including events we do not act on. A gateway
    // retries a non-2xx, and retrying an event nobody handles is a queue that never drains.
    return { received: true };
  }
}
