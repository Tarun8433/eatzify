import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiExcludeController } from '@nestjs/swagger';
import { timingSafeEqual } from 'crypto';
import type { AllConfigType } from '../../config/config.type';
import { PlayBillingService, type PubSubPush } from './play-billing.service';

/// Google Play real-time developer notifications, pushed by Pub/Sub (payments plan, Phase 4).
///
/// No bearer token — the caller is Google. The push URL carries a shared secret, and the message
/// itself is only a hint: the purchase is re-read from Google before anything changes.
@ApiExcludeController()
@Controller({ path: 'billing/play/notifications', version: '1' })
export class PlayNotificationController {
  constructor(
    private readonly play: PlayBillingService,
    private readonly config: ConfigService<AllConfigType>,
  ) {}

  @Post()
  @HttpCode(HttpStatus.NO_CONTENT)
  async receive(
    @Query('token') token: string | undefined,
    @Body() body: PubSubPush,
  ): Promise<void> {
    const expected = this.config.get('store.playRtdnToken', { infer: true });
    if (!expected || !token || !sameSecret(token, expected)) {
      throw new UnauthorizedException();
    }
    // A throw here answers 500, and Pub/Sub retries — which is what a failed Google read wants.
    await this.play.notification(body, new Date());
  }
}

function sameSecret(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}
