import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  AttributionEntity,
  CommissionEntryEntity,
  CommissionRateEntity,
  PartnerReferralEntity,
} from './entities/commission-entry.entity';
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
    ]),
  ],
  controllers: [PartnerController],
  providers: [CommissionService, ReferralService],
  // The payment webhook writes the ledger entry, and signup writes the attribution.
  exports: [CommissionService, ReferralService],
})
export class PartnerModule {}
