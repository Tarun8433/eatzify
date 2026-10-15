import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AppSettingEntity } from './app-setting.entity';
import { DashboardSwitchOverrideEntity } from './dashboard-switch-override.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import {
  DASHBOARD_SWITCH_AUDIENCE_KEY,
  DEFAULT_DASHBOARD_SWITCH_AUDIENCE,
  canSwitchDashboard,
  isDashboardSwitchAudience,
  type DashboardSwitchAudience,
} from './dashboard-switch';

/// What the admin sees for one person: their override, and what they get with it.
export type UserDashboardSwitchView = {
  user_id: number;
  /// null is "follow the app-wide setting".
  override: boolean | null;
  audience: DashboardSwitchAudience;
  allowed: boolean;
};

/// D-269. The app-wide audience and the per-person overrides, and the answer `/auth/me` carries.
@Injectable()
export class DashboardSwitchService {
  constructor(
    @InjectRepository(AppSettingEntity)
    private readonly settings: Repository<AppSettingEntity>,
    @InjectRepository(DashboardSwitchOverrideEntity)
    private readonly overrides: Repository<DashboardSwitchOverrideEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
  ) {}

  /// A missing or unreadable row is the default, never an error: `/auth/me` runs on every start.
  async audience(): Promise<DashboardSwitchAudience> {
    const row = await this.settings.findOneBy({
      key: DASHBOARD_SWITCH_AUDIENCE_KEY,
    });
    const value = row?.value;
    return isDashboardSwitchAudience(value)
      ? value
      : DEFAULT_DASHBOARD_SWITCH_AUDIENCE;
  }

  async setAudience(
    audience: DashboardSwitchAudience,
    byUserId: number,
  ): Promise<DashboardSwitchAudience> {
    await this.settings.save({
      key: DASHBOARD_SWITCH_AUDIENCE_KEY,
      value: audience,
      updatedByUserId: byUserId,
    });
    return audience;
  }

  async overrideFor(userId: number): Promise<boolean | null> {
    const row = await this.overrides.findOneBy({ userId });
    return row ? row.allowed : null;
  }

  /// null removes the override: the person follows the app-wide setting again.
  async setOverride(
    userId: number,
    allowed: boolean | null,
    byUserId: number,
  ): Promise<void> {
    if (allowed === null) {
      await this.overrides.delete({ userId });
      return;
    }
    await this.overrides.save({ userId, allowed, updatedByUserId: byUserId });
  }

  async allowedFor(
    userId: number,
    roleId: number | null | undefined,
  ): Promise<boolean> {
    const [audience, override] = await Promise.all([
      this.audience(),
      this.overrideFor(userId),
    ]);
    return canSwitchDashboard(roleId, audience, override);
  }

  /// For the admin's person page. 404 for an id that is no account.
  async viewFor(userId: number): Promise<UserDashboardSwitchView> {
    const user = await this.users.findOne({
      where: { id: userId },
      relations: { role: true },
    });
    if (!user) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'USER_NOT_FOUND', user_message: 'No such user.' },
      });
    }
    const [audience, override] = await Promise.all([
      this.audience(),
      this.overrideFor(userId),
    ]);
    return {
      user_id: userId,
      override,
      audience,
      allowed: canSwitchDashboard(user.role?.id, audience, override),
    };
  }
}
