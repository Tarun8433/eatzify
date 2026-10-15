import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppSettingEntity } from './app-setting.entity';
import { DashboardSwitchOverrideEntity } from './dashboard-switch-override.entity';
import { DashboardSwitchService } from './dashboard-switch.service';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      AppSettingEntity,
      DashboardSwitchOverrideEntity,
      UserEntity,
    ]),
  ],
  providers: [DashboardSwitchService],
  exports: [DashboardSwitchService],
})
export class DashboardSwitchModule {}
