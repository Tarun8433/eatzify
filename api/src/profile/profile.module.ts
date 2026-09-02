import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ProfileController } from './profile.controller';
import { ProfileService } from './profile.service';
import { ProfileEntity } from './entities/profile.entity';
import { HealthProfileEntity } from './entities/health-profile.entity';
import { ConsentEntity } from './entities/consent.entity';
import { ProfileChangeEntity } from './entities/profile-change.entity';
import { ProfileAuditService } from './profile-audit.service';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      ProfileEntity,
      HealthProfileEntity,
      ConsentEntity,
      ProfileChangeEntity,
    ]),
    UsersModule,
  ],
  controllers: [ProfileController],
  providers: [ProfileService, ProfileAuditService],
  exports: [ProfileService, ProfileAuditService],
})
export class ProfileModule {}
