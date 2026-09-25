import { randomBytes } from 'node:crypto';
import { HttpStatus, Injectable, ConflictException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  AttributionEntity,
  PartnerReferralEntity,
} from './entities/commission-entry.entity';

/**
 * Where a referral link points. Build-time, like every other environment-dependent URL — a literal
 * would send beta testers to the production listing.
 */
const LINK_BASE = process.env.REFERRAL_LINK_BASE ?? 'https://eatzify.app/join';

/**
 * No `0`, `O`, `1`, `I` or `5`/`S`.
 *
 * Codes get read aloud and copied off screens. A character somebody can mistype is a signup
 * attributed to nobody, which the partner cannot see and cannot dispute.
 */
const ALPHABET = 'ABCDEFGHJKLMNPQRTUVWXYZ2346789';
const CODE_LENGTH = 8;

export type ReferralView = { code: string; url: string };

/**
 * A partner's code, and the attribution it creates.
 *
 * docs/12 §3: first-touch, locked at signup, never rewritten. The `attribution` table's primary key
 * is on the CLIENT, so a second code for the same person is refused by the database rather than by
 * a check that has to remember — including on a reinstall, which is the case the doc calls out.
 */
@Injectable()
export class ReferralService {
  constructor(
    @InjectRepository(PartnerReferralEntity)
    private readonly referrals: Repository<PartnerReferralEntity>,
    @InjectRepository(AttributionEntity)
    private readonly attributions: Repository<AttributionEntity>,
  ) {}

  /// The partner's code, minted on first ask. Idempotent — a partner who opens the screen twice has
  /// one code, and a code that changed would strand every link already shared.
  async forPartner(partnerUserId: number): Promise<ReferralView> {
    const existing = await this.referrals.findOne({
      where: { userId: partnerUserId },
    });
    if (existing) return this.toView(existing.code);

    const code = await this.mintUnique();
    await this.referrals.save(
      this.referrals.create({ userId: partnerUserId, code }),
    );

    return this.toView(code);
  }

  /**
   * Lock a new account to the partner whose code they arrived with.
   *
   * Refuses to attribute somebody to themselves — docs/12 §7's cheapest self-referral check, and
   * the one the database also enforces. An unknown code attributes nobody rather than failing the
   * signup: a mistyped code should cost a commission, never an account.
   */
  async attribute({
    userId,
    code,
    channel,
  }: {
    userId: number;
    code: string;
    channel: 'code' | 'link' | 'qr';
  }): Promise<void> {
    const referral = await this.referrals.findOne({
      where: { code: code.trim().toUpperCase() },
    });
    if (!referral || referral.userId === userId) return;

    try {
      await this.attributions.save(
        this.attributions.create({
          userId,
          partnerUserId: referral.userId,
          codeUsed: referral.code,
          channel,
        }),
      );
    } catch {
      // Already attributed. docs/12 §3: "First one wins. No re-attribution ever." The second code
      // is not an error — it is simply too late, and saying so would leak who got there first.
    }
  }

  /// Who referred this account, or null. Read by the payment path to decide whose ledger a purchase
  /// lands on.
  async partnerFor(userId: number): Promise<number | null> {
    const row = await this.attributions.findOne({ where: { userId } });
    return row?.partnerUserId ?? null;
  }

  private async mintUnique(): Promise<string> {
    // Eight characters from a thirty-letter alphabet is 6.5e11 codes. Retrying on a collision is
    // still cheaper than reasoning about whether one can happen.
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const code = randomCode();
      const taken = await this.referrals.findOne({ where: { code } });
      if (!taken) return code;
    }

    throw new ConflictException({
      status: HttpStatus.CONFLICT,
      error: {
        code: 'REFERRAL_CODE_UNAVAILABLE',
        user_message:
          'We could not create your referral code. Please try again.',
      },
    });
  }

  private toView(code: string): ReferralView {
    return { code, url: `${LINK_BASE}/${code}` };
  }
}

function randomCode(): string {
  const bytes = randomBytes(CODE_LENGTH);
  let out = '';

  for (let i = 0; i < CODE_LENGTH; i += 1) {
    out += ALPHABET[bytes[i]! % ALPHABET.length];
  }

  return out;
}
