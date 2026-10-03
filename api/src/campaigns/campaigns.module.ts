import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { AnnouncementsService } from './announcements.service';
import { CampaignsController } from './campaigns.controller';
import { AnnouncementEntity } from './entities/announcement.entity';
import { DeviceTokenEntity } from './entities/device-token.entity';
import { NotificationCampaignEntity } from './entities/notification-campaign.entity';
import { PushService } from './push.service';

/// Admin panel plan, Phase C: push delivery and announcements. The admin screens that drive them
/// live in AdminModule, which imports this one.
@Module({
  imports: [
    // Not BillingModule: billing → partner → coach → admin → here would be a cycle.
    TypeOrmModule.forFeature([
      AnnouncementEntity,
      DeviceTokenEntity,
      NotificationCampaignEntity,
      SubscriptionEntity,
    ]),
  ],
  controllers: [CampaignsController],
  providers: [PushService, AnnouncementsService],
  exports: [PushService, AnnouncementsService, TypeOrmModule],
})
export class CampaignsModule {}
