import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CoachApplicationEntity } from './entities/coach-application.entity';
import { CoachGrantEntity } from './entities/coach-grant.entity';
import { CoachInviteEntity } from './entities/coach-invite.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { CoachApplicationService } from './coach-application.service';
import { CoachGrantService } from './coach-grant.service';
import { CoachInviteService } from './coach-invite.service';
import { CoachClientsService } from './coach-clients.service';
import { CoachProgressService } from './coach-progress.service';
import { CheckInsService } from './check-ins.service';
import { CheckInEntity } from './entities/check-in.entity';
import { MessagesService } from './messages.service';
import { ChatGateway } from './chat.gateway';
import { MessageEntity } from './entities/message.entity';
import { LogsModule } from '../logs/logs.module';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { MeasurementEntity } from '../measurements/entities/measurement.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { FoodLogEntity } from '../logs/entities/food-log.entity';
import { ClientMetricsService } from '../clients/client-metrics.service';
import { AdminModule } from '../admin/admin.module';
import { UsersModule } from '../users/users.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { JwtModule } from '@nestjs/jwt';
import { CoachController } from './coach.controller';

/// Coach onboarding (docs/12 §6). Deliberately owns no client data: an applicant has no clients,
/// and the surfaces that do are gated on a consent grant rather than on a role (docs/10 §1).
@Module({
  imports: [
    TypeOrmModule.forFeature([
      CoachApplicationEntity,
      CoachGrantEntity,
      CoachInviteEntity,
      CheckInEntity,
      MessageEntity,
      UserEntity,
      // The roster reads names and the age band off the profile.
      ProfileEntity,
      // Tier for the badge, weight series for the 30-day change, food logs for adherence.
      SubscriptionEntity,
      MeasurementEntity,
      FoodLogEntity,
    ]),
    // docs/10 §6: a coach opening a client's health fields writes an audit row, through the same
    // service every other audited read uses.
    AdminModule,
    // A coaching partner may read a client's diary, which LogsService already assembles.
    LogsModule,
    // The invite is addressed by phone, so answering one needs the caller's own number.
    UsersModule,
    // A completed check-in leaves the client a message (docs/02 FR-5.2).
    NotificationsModule,
    // The chat socket verifies the same token the REST guard does (docs/02 FR-5.5).
    JwtModule.register({}),
  ],
  controllers: [CoachController],
  providers: [
    CoachApplicationService,
    CoachGrantService,
    CoachInviteService,
    CoachClientsService,
    CoachProgressService,
    CheckInsService,
    MessagesService,
    ChatGateway,
    // Shared with the admin dashboard: "how is this client doing" must have one implementation.
    ClientMetricsService,
  ],
  // Exported because every coach-facing read has to ask it what the client allowed (docs/10 §1).
  exports: [
    CoachApplicationService,
    CoachGrantService,
    CoachInviteService,
    CoachClientsService,
    MessagesService,
  ],
})
export class CoachModule {}
