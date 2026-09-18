import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Ip,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsOptional, IsString, Matches } from 'class-validator';
import { Roles } from '../roles/roles.decorator';
import { RolesGuard } from '../roles/roles.guard';
import { RoleEnum } from '../roles/roles.enum';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import {
  TotpService,
  type TotpEnrolment,
  type TotpStatus,
} from './totp.service';
import { RulePacksService, type RulePackState } from './rule-packs.service';
import { AuditService } from './audit.service';

class TotpCodeDto {
  @Matches(/^\d{6}$/, { message: 'code must be six digits' })
  code: string;
}

/// docs/09 §9: `POST /admin/rule-packs/activate { version }`.
class ActivateRulePackDto {
  @IsString()
  version: string;

  /// docs/09 §9's `reviewed_by`: the other person. Their user id, because a name is not a record.
  @IsString()
  reviewed_by: string;

  @IsOptional()
  @IsString()
  note?: string;
}

/// The second factor, for anybody who can reach the admin surface.
@ApiTags('Admin')
@ApiBearerAuth()
@Roles(RoleEnum.admin, RoleEnum.super_admin)
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller({ path: 'admin/totp', version: '1' })
export class AdminTotpController {
  constructor(private readonly totp: TotpService) {}

  @Get()
  status(@Request() request: { user: JwtPayloadType }): Promise<TotpStatus> {
    return this.totp.status(Number(request.user.id));
  }

  /// Returns the secret once. It is never readable again — a lost phone means a reset, not a
  /// second look.
  @Post('enroll')
  @HttpCode(HttpStatus.OK)
  enroll(@Request() request: { user: JwtPayloadType }): Promise<TotpEnrolment> {
    const id = Number(request.user.id);
    // The label is what shows in the authenticator app's list. An id, not an email (rule 5).
    return this.totp.enroll(id, `admin ${id}`);
  }

  @Post('confirm')
  @HttpCode(HttpStatus.NO_CONTENT)
  confirm(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: TotpCodeDto,
  ): Promise<void> {
    return this.totp.confirm(Number(request.user.id), dto.code);
  }
}

/**
 * docs/09 §9: rule-pack activation. **super_admin only** — its own controller rather than a method
 * on `AdminController`, because that class is `@Roles(admin, super_admin)` and the guard resolves
 * the class's decorator first. A route whose protection depends on decorator precedence is a route
 * that loses its protection the day somebody reorders an argument.
 *
 * Both routes here are behind a TOTP code (D-229): this is the switch that decides which numbers
 * every plan in the country is generated from.
 */
@ApiTags('Admin')
@ApiBearerAuth()
@Roles(RoleEnum.super_admin)
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller({ path: 'admin/rule-packs', version: '1' })
export class AdminRulePacksController {
  constructor(
    private readonly packs: RulePacksService,
    private readonly totp: TotpService,
    private readonly audit: AuditService,
  ) {}

  /// What is live, what is on disk, and every switch that has ever been made.
  @Get()
  state(): Promise<RulePackState> {
    return this.packs.state();
  }

  @Post('activate')
  @HttpCode(HttpStatus.OK)
  async activate(
    @Body() dto: ActivateRulePackDto,
    @Headers('x-totp') code: string | undefined,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
  ): Promise<RulePackState> {
    const actorUserId = Number(request.user.id);
    await this.totp.require(actorUserId, code ?? '');

    const state = await this.packs.activate({
      version: dto.version,
      actorUserId,
      reviewedByUserId: Number(dto.reviewed_by),
      note: dto.note,
    });

    await this.audit.record({
      actorUserId,
      actorRole: String(request.user.role?.id ?? RoleEnum.super_admin),
      action: 'rule_pack_activate',
      resource: `rule-pack/${dto.version}`,
      ip,
      meta: { version: dto.version, reviewed_by: Number(dto.reviewed_by) },
    });

    return state;
  }
}
