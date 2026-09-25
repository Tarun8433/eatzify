import { ForbiddenException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AdminTotpEntity } from './entities/admin-totp.entity';
import { newSecret, otpauthUri, verifyTotp } from './totp';

export type TotpStatus = { enrolled: boolean };
export type TotpEnrolment = { secret: string; otpauth_uri: string };

/**
 * The second factor in front of the dangerous admin actions (D-229): activating a rule pack, and
 * revealing somebody's full identity.
 *
 * Deliberately NOT on every login. A code demanded thirty times a day is a code typed without
 * reading it, and the actions that matter here are rare enough that asking for one is a pause, not
 * a tax.
 */
@Injectable()
export class TotpService {
  constructor(
    @InjectRepository(AdminTotpEntity)
    private readonly totp: Repository<AdminTotpEntity>,
  ) {}

  async status(userId: number): Promise<TotpStatus> {
    const row = await this.totp.findOne({ where: { userId } });
    return { enrolled: row?.confirmedAt != null };
  }

  /**
   * Starts enrolment, returning the only copy of the secret this endpoint will ever hand out.
   *
   * An unconfirmed row is replaced rather than kept: somebody who lost the QR code halfway through
   * needs a new one, and nothing is protected by the half-finished secret.
   */
  async enroll(userId: number, label: string): Promise<TotpEnrolment> {
    const existing = await this.totp.findOne({ where: { userId } });
    if (existing?.confirmedAt) {
      throw new ForbiddenException({
        error: {
          code: 'TOTP_ALREADY_ENROLLED',
          user_message:
            'An authenticator is already set up for this account. Ask another super admin to reset it.',
        },
      });
    }

    const secret = newSecret();
    await this.totp.save(
      this.totp.create({
        userId,
        secret,
        confirmedAt: null,
        lastCode: null,
        lastUsedAt: null,
      }),
    );

    return { secret, otpauth_uri: otpauthUri(secret, label) };
  }

  /// Proves the app is actually set up before anything starts depending on it.
  async confirm(userId: number, code: string, now = new Date()): Promise<void> {
    const row = await this.totp.findOne({ where: { userId } });
    if (!row || row.confirmedAt) {
      throw new ForbiddenException({
        error: {
          code: 'TOTP_NOT_STARTED',
          user_message: 'Start the setup again — there is nothing to confirm.',
        },
      });
    }
    if (!verifyTotp(row.secret, code, now)) throw this.invalid();

    row.confirmedAt = now;
    row.lastCode = code;
    row.lastUsedAt = now;
    await this.totp.save(row);
  }

  /**
   * The gate itself. Throws unless this person typed a code from their own app that has not been
   * used before.
   */
  async require(userId: number, code: string, now = new Date()): Promise<void> {
    const row = await this.totp.findOne({ where: { userId } });
    if (!row?.confirmedAt) {
      throw new ForbiddenException({
        error: {
          code: 'TOTP_REQUIRED',
          user_message:
            'This action needs an authenticator app. Set one up under Security first.',
        },
      });
    }

    if (!verifyTotp(row.secret, code, now)) throw this.invalid();

    // A code is good once. Without this, a code read over somebody's shoulder is usable for the
    // rest of its window.
    if (row.lastCode === code) {
      throw new ForbiddenException({
        error: {
          code: 'TOTP_REUSED',
          user_message: 'That code has been used. Wait for the next one.',
        },
      });
    }

    row.lastCode = code;
    row.lastUsedAt = now;
    await this.totp.save(row);
  }

  private invalid(): ForbiddenException {
    return new ForbiddenException({
      error: {
        code: 'TOTP_INVALID',
        user_message: 'That code is not right. Try the current one.',
      },
    });
  }
}
