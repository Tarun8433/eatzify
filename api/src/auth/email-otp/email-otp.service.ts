import { HttpException, HttpStatus, Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { MoreThan, Repository } from 'typeorm';
import { MailService } from '../../mail/mail.service';
import {
  CODE_EMAIL_TITLE,
  CODE_RATE_LIMITED,
  CODE_SEND_FAILED,
  codeEmailBody,
} from '../auth-copy';
import { EmailOtpEntity } from './email-otp.entity';
import {
  check,
  type CheckResult,
  CODE_TTL_MS,
  hashCode,
  HOUR_MS,
  MAX_SENDS_PER_HOUR,
  newCode,
} from './email-otp.rules';

/// Sends and checks the 6-digit sign-up codes (D-250). The rules are in `email-otp.rules.ts`;
/// this only stores, counts and emails.
@Injectable()
export class EmailOtpService {
  private readonly logger = new Logger(EmailOtpService.name);

  constructor(
    @InjectRepository(EmailOtpEntity)
    private readonly codes: Repository<EmailOtpEntity>,
    private readonly mail: MailService,
  ) {}

  async issue(userId: number, email: string, now = new Date()): Promise<void> {
    const recent = await this.codes.count({
      where: { userId, createdAt: MoreThan(new Date(now.getTime() - HOUR_MS)) },
    });
    if (recent >= MAX_SENDS_PER_HOUR) {
      throw new HttpException(
        {
          status: HttpStatus.TOO_MANY_REQUESTS,
          error: { code: 'CODE_RATE_LIMITED', user_message: CODE_RATE_LIMITED },
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const code = newCode();
    const row = await this.codes.save(
      this.codes.create({
        userId,
        codeHash: hashCode(code),
        expiresAt: new Date(now.getTime() + CODE_TTL_MS),
        attempts: 0,
      }),
    );
    try {
      await this.mail.notification({
        to: email,
        data: { title: CODE_EMAIL_TITLE, body: codeEmailBody(code) },
      });
    } catch (e) {
      // SMTP refused (wrong MAIL_* settings, a revoked app password, the daily cap). The message
      // is the mail server's, never the address (api rule 5). A code nobody received must not
      // count against the hourly limit.
      this.logger.error(
        `code email failed for user ${userId}: ${(e as Error).message}`,
      );
      await this.codes.delete({ id: row.id });
      throw new HttpException(
        {
          status: HttpStatus.SERVICE_UNAVAILABLE,
          error: { code: 'CODE_SEND_FAILED', user_message: CODE_SEND_FAILED },
        },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }

  /// Checks a guess against the newest code. A wrong guess costs an attempt; the right one
  /// consumes every code this person has, so none can be replayed.
  async verify(
    userId: number,
    code: string,
    now = new Date(),
  ): Promise<CheckResult> {
    const latest = await this.codes.findOne({
      where: { userId },
      order: { createdAt: 'DESC', id: 'DESC' },
    });
    const result = check(latest, code, now);
    if (result === 'wrong' && latest) {
      await this.codes.update(latest.id, { attempts: latest.attempts + 1 });
    }
    if (result === 'ok') await this.codes.delete({ userId });
    return result;
  }
}
