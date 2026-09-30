import {
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import type { AllConfigType } from '../config/config.type';
import { decryptField, encryptField } from '../utils/field-crypto';
import { PartnerKycEntity } from './entities/payout.entity';
import { PAYOUT_MINIMUM_PAISE } from './payout-rules';
import { PayoutService } from './payout.service';

const KYC_NOT_CONFIGURED =
  "Payout details can't be saved right now. Please try again later.";
const KYC_NOT_FOUND = 'This partner has not sent payout details.';

/// What the partner's app shows. `required` is the only thing that makes it ask — KYC is requested
/// when there is money to pay, never before (D-255).
export type KycView = {
  required: boolean;
  status: 'none' | 'pending' | 'verified' | 'rejected';
  due_paise: string;
  holder_name: string | null;
  pan_last4: string | null;
  bank_last4: string | null;
  ifsc: string | null;
  gstin: string | null;
};

export type KycSubmission = {
  holderName: string;
  pan: string;
  accountNumber: string;
  ifsc: string;
  gstin: string | null;
};

/// The admin's view once they have passed the second factor: enough to send the transfer.
export type KycReveal = {
  status: string;
  holder_name: string | null;
  pan: string | null;
  account_number: string | null;
  ifsc: string | null;
  gstin: string | null;
};

/**
 * docs/12 §5's KYC, collected from the partner in the app (D-255).
 *
 * Asked for only once a payout is actually due. The full PAN and account number are sealed with a
 * key that is not in the database; the last four stay readable for the partner's own screen.
 */
@Injectable()
export class KycService {
  constructor(
    @InjectRepository(PartnerKycEntity)
    private readonly kyc: Repository<PartnerKycEntity>,
    private readonly payouts: PayoutService,
    private readonly config: ConfigService<AllConfigType>,
  ) {}

  async viewFor(partnerUserId: number, now: Date): Promise<KycView> {
    const [row, due] = await Promise.all([
      this.kyc.findOne({ where: { partnerUserId } }),
      this.payouts.settleableBalance(partnerUserId, now),
    ]);
    const status = row?.status ?? 'none';
    return {
      // Pending is waiting on us, not on them; verified is done.
      required:
        due >= PAYOUT_MINIMUM_PAISE &&
        (status === 'none' || status === 'rejected'),
      status,
      due_paise: due.toString(),
      holder_name: row?.holderName ?? null,
      pan_last4: row?.panLast4 ?? null,
      bank_last4: row?.bankLast4 ?? null,
      ifsc: row?.ifsc ?? null,
      gstin: row?.gstin ?? null,
    };
  }

  /// A new or changed submission goes back to `pending` for an admin to check. A changed account
  /// restarts the 7-day freeze (docs/12 §7).
  async submit(
    partnerUserId: number,
    input: KycSubmission,
    now: Date,
  ): Promise<KycView> {
    const key = this.key();
    const existing = await this.kyc.findOne({ where: { partnerUserId } });
    const previousAccount = existing?.accountSealed
      ? decryptField(existing.accountSealed, key)
      : null;
    const bankChanged =
      !existing ||
      previousAccount !== input.accountNumber ||
      existing.ifsc !== input.ifsc;

    await this.kyc.save({
      ...(existing ?? {}),
      partnerUserId,
      holderName: input.holderName,
      ifsc: input.ifsc,
      gstin: input.gstin,
      panLast4: input.pan.slice(-4),
      bankLast4: input.accountNumber.slice(-4),
      panSealed: encryptField(input.pan, key),
      accountSealed: encryptField(input.accountNumber, key),
      status: 'pending' as const,
      verifiedAt: null,
      bankChangedAt: bankChanged ? now : existing.bankChangedAt,
    });
    return this.viewFor(partnerUserId, now);
  }

  /// Admin only, behind TOTP and a `read_pii` audit row in the controller.
  async reveal(partnerUserId: number): Promise<KycReveal> {
    const row = await this.found(partnerUserId);
    const key = this.key();
    return {
      status: row.status,
      holder_name: row.holderName,
      pan: row.panSealed ? decryptField(row.panSealed, key) : null,
      account_number: row.accountSealed
        ? decryptField(row.accountSealed, key)
        : null,
      ifsc: row.ifsc,
      gstin: row.gstin,
    };
  }

  async review(
    partnerUserId: number,
    status: 'verified' | 'rejected',
    now: Date,
  ): Promise<void> {
    const row = await this.found(partnerUserId);
    await this.kyc.save({
      ...row,
      status,
      verifiedAt: status === 'verified' ? now : null,
    });
  }

  private async found(partnerUserId: number): Promise<PartnerKycEntity> {
    const row = await this.kyc.findOne({ where: { partnerUserId } });
    if (!row) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'KYC_NOT_FOUND', user_message: KYC_NOT_FOUND },
      });
    }
    return row;
  }

  private key(): string {
    const key = this.config.get('invoice.kycFieldKey', { infer: true });
    if (key) return key;
    throw new HttpException(
      {
        status: HttpStatus.SERVICE_UNAVAILABLE,
        error: { code: 'KYC_NOT_CONFIGURED', user_message: KYC_NOT_CONFIGURED },
      },
      HttpStatus.SERVICE_UNAVAILABLE,
    );
  }
}
