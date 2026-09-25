import { BillingModule } from '../billing/billing.module';
import { PaymentOrderEntity } from '../billing/entities/payment-order.entity';
import { CouponEntity } from '../billing/entities/coupon.entity';
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CoachApplicationEntity } from '../coach/entities/coach-application.entity';
import { CoachGrantEntity } from '../coach/entities/coach-grant.entity';
import { CoachInviteEntity } from '../coach/entities/coach-invite.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { AdminController } from './admin.controller';
import { AdminCoachService } from './admin-coach.service';
import { AdminClientsService } from './admin-clients.service';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { FoodLogEntity } from '../logs/entities/food-log.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { PlanEntity } from '../plans/entities/plan.entity';
import { HealthProfileEntity } from '../profile/entities/health-profile.entity';
import { ConsentEntity } from '../profile/entities/consent.entity';
import { AdminMetricsService } from './admin-metrics.service';
import { AdminAudienceService } from './admin-audience.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { FoodsModule } from '../foods/foods.module';
import { AuditService } from './audit.service';
import { AuditLogEntity } from './entities/audit-log.entity';
import { FilesModule } from '../files/files.module';
import { TicketsModule } from '../tickets/tickets.module';
import { PlansModule } from '../plans/plans.module';
import { AdminTotpEntity } from './entities/admin-totp.entity';
import { RulePackActivationEntity } from './entities/rule-pack-activation.entity';
import {
  AdminRulePacksController,
  AdminTotpController,
} from './admin-security.controller';
import { TotpService } from './totp.service';
import { RulePacksService } from './rule-packs.service';

/// docs/09 §9. Reads across several domains on purpose — an overview that had to go through each
/// owning module's service would either need a counting method added to every one of them, or a
/// join the modules cannot express between them.
///
/// `AuditService` is exported: the audit trail is not the admin module's private business, and rule
/// 9 in `api/CLAUDE.md` ("every endpoint returning a health field gets the audit interceptor") means
/// the rest of the app has to be able to write to it.
@Module({
  imports: [
    BillingModule,
    TypeOrmModule.forFeature([
      PaymentOrderEntity,
      CouponEntity,
      AuditLogEntity,
      AdminTotpEntity,
      RulePackActivationEntity,
      CoachApplicationEntity,
      CoachGrantEntity,
      CoachInviteEntity,
      SubscriptionEntity,
      UserEntity,
      ProfileEntity,
      FoodLogEntity,
      MeasurementEntity,
      PlanEntity,
      HealthProfileEntity,
      ConsentEntity,
    ]),
    // For resolving a document's stored path. The bytes are streamed by this module, never linked.
    FilesModule,
    // docs/09 §9's broadcast writes the same rows the app already lists (D-223).
    NotificationsModule,
    // The food review queue is the foods module's own service, reached from the admin surface
    // rather than reimplemented beside it (D-227).
    FoodsModule,
    // Support conversations are the tickets module's own rows, read from the other side (D-228).
    TicketsModule,
    // The engine owns the rule packs; activation only chooses which of them is live (D-229).
    PlansModule,
  ],
  controllers: [AdminController, AdminTotpController, AdminRulePacksController],
  providers: [
    AdminMetricsService,
    AdminCoachService,
    AdminClientsService,
    AdminAudienceService,
    AuditService,
    TotpService,
    RulePacksService,
  ],
  exports: [AuditService, TotpService],
})
export class AdminModule {}
