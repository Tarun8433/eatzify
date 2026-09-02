import { UnprocessableEntityException } from '@nestjs/common';
import { OtpService } from '../src/auth/otp.service';

/// Pulls the server-authored `user_message` out of a thrown 422 body.
function userMessageOf(fn: () => void): string {
  try {
    fn();
  } catch (e) {
    const body = (e as UnprocessableEntityException).getResponse() as {
      error?: { user_message?: string };
    };
    return body.error?.user_message ?? '';
  }
  return '';
}

const PHONE = '+919876500099';
const CODE = '000000';
const HOUR = 60 * 60 * 1000;

describe('OtpService', () => {
  let service: OtpService;
  const now = 1_700_000_000_000;

  beforeEach(() => {
    service = new OtpService();
  });

  it('accepts the issued code once, then rejects a replay', () => {
    service.issue(PHONE, now);

    expect(() => service.consume(PHONE, CODE, now)).not.toThrow();
    expect(() => service.consume(PHONE, CODE, now)).toThrow();
  });

  it('rejects a wrong code', () => {
    service.issue(PHONE, now);

    expect(() => service.consume(PHONE, '123456', now)).toThrow();
  });

  it('rejects a code past its 5 minute ttl', () => {
    service.issue(PHONE, now);

    expect(() =>
      service.consume(PHONE, CODE, now + 5 * 60 * 1000 + 1),
    ).toThrow();
  });

  it('locks out after 5 wrong attempts', () => {
    service.issue(PHONE, now);
    for (let i = 0; i < 5; i++) {
      expect(() => service.consume(PHONE, '123456', now)).toThrow();
    }

    // correct code no longer helps — the entry is burned
    expect(() => service.consume(PHONE, CODE, now)).toThrow();
  });

  it('rate limits to 3 sends per hour per number, and recovers after the window', () => {
    service.issue(PHONE, now);
    service.issue(PHONE, now);
    service.issue(PHONE, now);

    // rule 7: the user-facing string is the server's `user_message`, not the exception message.
    expect(() => service.issue(PHONE, now)).toThrow(
      UnprocessableEntityException,
    );
    expect(userMessageOf(() => service.issue(PHONE, now))).toMatch(
      /Too many code requests/,
    );
    expect(() => service.issue(PHONE, now + HOUR + 1)).not.toThrow();
  });

  it('rate limits per number, not globally', () => {
    service.issue(PHONE, now);
    service.issue(PHONE, now);
    service.issue(PHONE, now);

    expect(() => service.issue('+919876500098', now)).not.toThrow();
  });
});
