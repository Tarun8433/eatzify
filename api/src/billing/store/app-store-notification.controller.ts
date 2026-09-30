import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { AppStoreBillingService } from './app-store-billing.service';

/// App Store Server Notifications v2 (payments plan, Phase 5). No bearer token — the caller is
/// Apple, and the payload is a JWS whose signature is checked against Apple's root certificates.
@ApiExcludeController()
@Controller({ path: 'billing/appstore/notifications', version: '1' })
export class AppStoreNotificationController {
  constructor(private readonly apple: AppStoreBillingService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  async receive(@Body() body: { signedPayload?: unknown }): Promise<void> {
    if (typeof body?.signedPayload !== 'string') return;
    // A throw answers 500 and Apple retries — which is what a failed Apple read wants.
    await this.apple.notification(body.signedPayload, new Date());
  }
}
