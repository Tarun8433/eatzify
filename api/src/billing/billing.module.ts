import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BillingController } from './billing.controller';
import { CashfreeWebhookController } from './cashfree-webhook.controller';
import { BillingService } from './billing.service';
import { CheckoutService } from './checkout.service';
import { CashfreeClient } from './cashfree.client';
import { SubscriptionService } from './subscription.service';
import { SubscriptionSweepService } from './subscription-sweep.service';
import { RefundService } from './refund.service';
import { SubscriptionScheduler } from './subscription.scheduler';
import { SubscriptionEntity } from './entities/subscription.entity';
import { TrialGrantEntity } from './entities/trial-grant.entity';
import { CouponEntity } from './entities/coupon.entity';
import { CouponsService } from './coupons.service';
import { PaymentOrderEntity } from './entities/payment-order.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { PartnerModule } from '../partner/partner.module';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      CouponEntity,
      SubscriptionEntity,
      TrialGrantEntity,
      PaymentOrderEntity,
      // Cashfree needs a contactable customer, and the number lives on the user row.
      UserEntity,
    ]),
    // A confirmed payment credits whoever referred the buyer (docs/12 §3).
    PartnerModule,
    // A cancel, a trial ending and a renewal all leave the person a message (docs/11 §6, §8).
    NotificationsModule,
  ],
  controllers: [BillingController, CashfreeWebhookController],
  providers: [
    CouponsService,
    BillingService,
    CheckoutService,
    SubscriptionService,
    SubscriptionSweepService,
    SubscriptionScheduler,
    RefundService,
    CashfreeClient,
  ],
  exports: [
    BillingService,
    SubscriptionService,
    SubscriptionSweepService,
    CouponsService,
  ],
})
export class BillingModule {}
