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
import { RefundRequestService } from './refund-request.service';
import { RefundRequestEntity } from './entities/refund-request.entity';
import { PriceService } from './price.service';
import { PlayClient } from './store/play.client';
import { InvoiceEntity } from './invoice/invoice.entity';
import { InvoiceService } from './invoice/invoice.service';
import { PlayBillingService } from './store/play-billing.service';
import { StoreGrantService } from './store/store-grant.service';
import { PlayNotificationController } from './store/play-notification.controller';
import { AppStoreClient } from './store/app-store.client';
import { AppStoreBillingService } from './store/app-store-billing.service';
import { AppStoreNotificationController } from './store/app-store-notification.controller';
import { TierPriceEntity } from './entities/tier-price.entity';
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
      RefundRequestEntity,
      TierPriceEntity,
      InvoiceEntity,
      // Cashfree needs a contactable customer, and the number lives on the user row.
      UserEntity,
    ]),
    // A confirmed payment credits whoever referred the buyer (docs/12 §3).
    PartnerModule,
    // A cancel, a trial ending and a renewal all leave the person a message (docs/11 §6, §8).
    NotificationsModule,
  ],
  controllers: [
    BillingController,
    CashfreeWebhookController,
    PlayNotificationController,
    AppStoreNotificationController,
  ],
  providers: [
    CouponsService,
    PriceService,
    PlayClient,
    PlayBillingService,
    AppStoreClient,
    AppStoreBillingService,
    InvoiceService,
    StoreGrantService,
    BillingService,
    CheckoutService,
    SubscriptionService,
    SubscriptionSweepService,
    SubscriptionScheduler,
    RefundService,
    RefundRequestService,
    CashfreeClient,
  ],
  exports: [
    BillingService,
    RefundService,
    RefundRequestService,
    SubscriptionService,
    SubscriptionSweepService,
    CouponsService,
  ],
})
export class BillingModule {}
