import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  AttributionEntity,
  CommissionEntryEntity,
  CommissionRateEntity,
  PartnerReferralEntity,
} from './entities/commission-entry.entity';
import {
  PartnerKycEntity,
  PayoutEntity,
  TdsRateEntity,
} from './entities/payout.entity';
import { PayoutService } from './payout.service';
import { KycService } from './kyc.service';
import { PayoutScheduler } from './payout.scheduler';
import { CommissionService } from './commission.service';
import { ReferralService } from './referral.service';
import { PartnerController } from './partner.controller';

/**
 * docs/12. What a partner earned and the code that earned it.
 *
 * Separate from `CoachModule` on purpose: coaching is a consent relationship with one client, and
 * commission is a commercial relationship with the platform. A level 1 affiliate has the second and
 * none of the first, and merging the two modules is how an affiliate ends up with a client list.
 */
@Module({
  imports: [
    TypeOrmModule.forFeature([
      CommissionEntryEntity,
      CommissionRateEntity,
      AttributionEntity,
      PartnerReferralEntity,
      PayoutEntity,
      PartnerKycEntity,
      TdsRateEntity,
    ]),
  ],
  controllers: [PartnerController],
  providers: [
    CommissionService,
    ReferralService,
    PayoutService,
    PayoutScheduler,
    KycService,
  ],
  // The payment webhook writes the ledger entry, and signup writes the attribution.
  // The admin payout desk drives PayoutService.
  exports: [CommissionService, ReferralService, PayoutService, KycService],
})
export class PartnerModule {}
