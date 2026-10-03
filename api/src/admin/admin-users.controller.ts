import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Ip,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import { RoleEnum } from '../roles/roles.enum';
import {
  BLOCK_REASONS,
  type BlockReason,
} from '../users/infrastructure/persistence/relational/entities/user-block.entity';
import {
  AdminUsersService,
  MAX_PAGE,
  type AccountState,
  type Actor,
  type AdminUserDetail,
  type AdminUserRow,
  type BlockDuration,
} from './admin-users.service';
import {
  AdminStaffService,
  ASSIGNABLE_ROLES,
  type StaffRow,
} from './admin-staff.service';
import { AUDIT_REASONS, type AuditReason } from './entities/audit-log.entity';
import { Permit, PermissionsGuard } from './permissions.guard';
import { can, permissionsFor, type Permission } from './permissions';
import {
  AdminDashboardService,
  SERIES_METRICS,
  type DashboardToday,
  type SeriesMetric,
  type SeriesPoint,
} from './admin-dashboard.service';
import { TotpService } from './totp.service';

class UserListQuery {
  @IsOptional()
  @IsIn(['active', 'unverified', 'blocked'])
  state?: AccountState;

  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  cursor?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_PAGE)
  limit?: number;
}

class SeriesQuery {
  @IsIn([...SERIES_METRICS])
  metric: SeriesMetric;

  @IsDateString()
  from: string;

  @IsDateString()
  to: string;
}

class RevealDto {
  @IsIn([...AUDIT_REASONS])
  reason: AuditReason;
}

class BlockDto {
  @IsIn([...BLOCK_REASONS])
  reason: BlockReason;

  @IsIn(['24h', '7d', '30d', 'permanent'])
  duration: BlockDuration;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}

class UpdateUserDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  first_name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  last_name?: string;
}

class RoleDto {
  @IsIn(ASSIGNABLE_ROLES)
  role_id: RoleEnum;
}

type StaffRequest = { user: JwtPayloadType };

/// Admin panel plan, Phase A: accounts, verification and staff.
@ApiTags('Admin')
@ApiBearerAuth()
@Permit('users.read')
@UseGuards(AuthGuard('jwt'), PermissionsGuard)
@Controller({ path: 'admin', version: '1' })
export class AdminUsersController {
  constructor(
    private readonly users: AdminUsersService,
    private readonly staffService: AdminStaffService,
    private readonly totp: TotpService,
    private readonly dashboard: AdminDashboardService,
  ) {}

  /// The home screen. Money is left out for a role that may not see payments.
  @Permit('users.read')
  @Get('dashboard')
  async today(
    @Request() request: StaffRequest,
  ): Promise<Omit<DashboardToday, 'payments'> & Partial<DashboardToday>> {
    const today = await this.dashboard.today();
    if (can(request.user.role?.id, 'payments.read')) return today;
    const { payments: _payments, ...rest } = today;
    void _payments;
    return rest;
  }

  @Permit('reports.read')
  @Get('metrics/series')
  series(@Query() q: SeriesQuery): Promise<SeriesPoint[]> {
    return this.dashboard.series(q.metric, new Date(q.from), new Date(q.to));
  }

  /// What this staff member may open — the dashboard builds its sidebar from it.
  @Permit('panel.access')
  @Get('me')
  me(@Request() request: StaffRequest): {
    user_id: number;
    role_id: number;
    permissions: Permission[];
  } {
    return {
      user_id: Number(request.user.id),
      role_id: Number(request.user.role?.id),
      permissions: permissionsFor(request.user.role?.id),
    };
  }

  @Get('users')
  list(
    @Query() q: UserListQuery,
  ): Promise<{ rows: AdminUserRow[]; next_cursor: number | null }> {
    return this.users.list({
      state: q.state,
      from: q.from ? new Date(q.from) : undefined,
      to: q.to ? new Date(q.to) : undefined,
      cursor: q.cursor,
      limit: q.limit,
    });
  }

  @Get('users/counts')
  counts(): Promise<Record<AccountState, number>> {
    return this.users.counts();
  }

  @Get('users/:id')
  detail(@Param('id', ParseIntPipe) id: number): Promise<AdminUserDetail> {
    return this.users.detail(id);
  }

  @Permit('users.reveal')
  @Post('users/:id/reveal')
  @HttpCode(HttpStatus.OK)
  reveal(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: RevealDto,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<{ email: string | null; phone: string | null }> {
    return this.users.reveal(id, dto.reason, actorOf(request, ip));
  }

  @Permit('users.manage')
  @Post('users/:id/block')
  @HttpCode(HttpStatus.OK)
  block(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: BlockDto,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<AdminUserDetail> {
    return this.users.block(id, dto, actorOf(request, ip));
  }

  @Permit('users.manage')
  @Post('users/:id/unblock')
  @HttpCode(HttpStatus.OK)
  unblock(
    @Param('id', ParseIntPipe) id: number,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<AdminUserDetail> {
    return this.users.unblock(id, actorOf(request, ip));
  }

  @Permit('users.manage')
  @Patch('users/:id')
  update(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: UpdateUserDto,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<AdminUserDetail> {
    return this.users.update(id, dto, actorOf(request, ip));
  }

  /// Super admin only (`staff.manage`), and a second factor: a deleted account is hard to explain.
  @Permit('staff.manage')
  @Delete('users/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async remove(
    @Param('id', ParseIntPipe) id: number,
    @Headers('x-totp') code: string | undefined,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<void> {
    await this.totp.require(Number(request.user.id), code ?? '');
    await this.users.remove(id, actorOf(request, ip));
  }

  @Permit('users.manage')
  @Post('users/:id/password-reset')
  @HttpCode(HttpStatus.NO_CONTENT)
  passwordReset(
    @Param('id', ParseIntPipe) id: number,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<void> {
    return this.users.sendPasswordReset(id, actorOf(request, ip));
  }

  @Permit('users.manage')
  @Post('users/:id/resend-verification')
  @HttpCode(HttpStatus.NO_CONTENT)
  resendVerification(
    @Param('id', ParseIntPipe) id: number,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<void> {
    return this.users.resendVerification(id, actorOf(request, ip));
  }

  @Permit('users.read')
  @Get('verification/summary')
  verificationSummary(): ReturnType<AdminStaffService['verificationSummary']> {
    return this.staffService.verificationSummary();
  }

  @Permit('users.read')
  @Get('verification/email')
  unverified(): Promise<AdminUserRow[]> {
    return this.users.unverified();
  }

  @Permit('staff.manage')
  @Get('staff')
  staff(): Promise<StaffRow[]> {
    return this.staffService.staff();
  }

  @Permit('staff.manage')
  @Post('staff/:id/role')
  @HttpCode(HttpStatus.OK)
  async setRole(
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: RoleDto,
    @Headers('x-totp') code: string | undefined,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<StaffRow[]> {
    await this.totp.require(Number(request.user.id), code ?? '');
    return this.staffService.setRole(id, dto.role_id, actorOf(request, ip));
  }
}

function actorOf(request: StaffRequest, ip: string): Actor {
  return {
    userId: Number(request.user.id),
    roleId: Number(request.user.role?.id),
    ip,
  };
}
