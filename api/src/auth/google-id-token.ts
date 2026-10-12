import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import type { AllConfigType } from '../config/config.type';
import type { SocialInterface } from '../social/interfaces/social.interface';

/// Google's ID token, checked against Google's keys. Thin on purpose, so `AuthService` is tested
/// without a network. The audience is the WEB client id: the app passes it as `serverClientId`, so
/// Android and iOS tokens both carry it. Null for anything that does not verify.
@Injectable()
export class GoogleIdToken {
  private readonly client = new OAuth2Client();

  constructor(private readonly config: ConfigService<AllConfigType>) {}

  async verify(idToken: string): Promise<SocialInterface | null> {
    const audience = this.config.get('auth.googleWebClientId', { infer: true });
    if (!audience) return null;
    try {
      const ticket = await this.client.verifyIdToken({ idToken, audience });
      const p = ticket.getPayload();
      if (!p?.sub) return null;
      return {
        id: p.sub,
        email: p.email,
        emailVerified: p.email_verified === true,
        firstName: p.given_name,
        lastName: p.family_name,
      };
    } catch {
      // Expired, wrong audience, bad signature: all the same answer to the caller.
      return null;
    }
  }
}
