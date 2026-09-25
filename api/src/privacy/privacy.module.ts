import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PrivacyRequestEntity } from './entities/privacy-request.entity';
import { PrivacyController } from './privacy.controller';
import { PrivacyService } from './privacy.service';
import { PrivacySweepService } from './privacy-sweep.service';
import { PrivacyScheduler } from './privacy.scheduler';
import { ConsentEntity } from '../profile/entities/consent.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { NotificationsModule } from '../notifications/notifications.module';

/// docs/13 §9. Exported because plan generation has to ask whether health processing is still
/// consented to (docs/13 §3) — a withdrawal that only changed a screen would be decoration.
@Module({
  imports: [
    TypeOrmModule.forFeature([PrivacyRequestEntity, ConsentEntity, UserEntity]),
    NotificationsModule,
  ],
  controllers: [PrivacyController],
  providers: [PrivacyService, PrivacySweepService, PrivacyScheduler],
  exports: [PrivacyService],
})
export class PrivacyModule {}
