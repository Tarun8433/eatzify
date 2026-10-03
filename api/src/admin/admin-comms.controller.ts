import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Ip,
  NotFoundException,
  Param,
  Patch,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayNotEmpty,
  IsArray,
  IsDateString,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import {
  CouponsService,
  type CouponView,
  type OfferStats,
} from '../billing/coupons.service';
import {
  AnnouncementsService,
  type AnnouncementView,
} from '../campaigns/announcements.service';
import {
  ANNOUNCEMENT_AUDIENCES,
  ANNOUNCEMENT_PRIORITIES,
  type AnnouncementAudience,
  type AnnouncementPriority,
} from '../campaigns/entities/announcement.entity';
import {
  CHANNELS,
  type Channel,
} from '../campaigns/entities/notification-campaign.entity';
import {
  CONTENT_CLASSES,
  type ContentClass,
} from '../notifications/entities/notification.entity';
import { AdminAlertsService, type AdminAlert } from './admin-alerts.service';
import {
  AdminCampaignsService,
  type CampaignView,
} from './admin-campaigns.service';
import { SegmentDto } from './admin.controller';
import type { Actor } from './admin-users.service';
import { AuditService } from './audit.service';
import { Permit, PermissionsGuard } from './permissions.guard';
import { TotpService } from './totp.service';

class CampaignSegmentDto extends SegmentDto {
  @IsOptional()
  @IsIn(['active', 'unverified'])
  account_state?: 'active' | 'unverified';
}

class PreviewDto {
  @IsIn([...CONTENT_CLASSES])
  content_class: ContentClass;

  @ValidateNested()
  @Type(() => CampaignSegmentDto)
  segment: CampaignSegmentDto;
}

class CampaignDto extends PreviewDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  title: string;

  @IsString()
  @MinLength(2)
  @MaxLength(1000)
  body: string;

  @IsArray()
  @ArrayNotEmpty()
  @IsIn([...CHANNELS], { each: true })
  channels: Channel[];

  @IsOptional()
  @IsDateString()
  scheduled_at?: string;
}

class AnnouncementDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  title: string;

  @IsString()
  @MinLength(2)
  @MaxLength(2000)
  body: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  image_url?: string | null;

  @IsIn([...ANNOUNCEMENT_PRIORITIES])
  priority: AnnouncementPriority;

  @IsIn([...ANNOUNCEMENT_AUDIENCES])
  audience: AnnouncementAudience;

  @IsOptional()
  @IsDateString()
  starts_at?: string;

  @IsOptional()
  @IsDateString()
  ends_at?: string | null;
}

class OfferUpdateDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  title?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  description?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  banner_url?: string | null;

  @IsOptional()
  @IsDateString()
  starts_at?: string | null;

  @IsOptional()
  @IsDateString()
  expires_at?: string | null;

  @IsOptional()
  @IsIn(['all', 'new_users'])
  eligibility?: 'all' | 'new_users';

  @IsOptional()
  @IsIn(['BASIC', 'PRO', null])
  tier?: 'BASIC' | 'PRO' | null;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  max_uses?: number;
}

const ANNOUNCEMENT_ACTIONS = {
  publish: 'published',
  unpublish: 'draft',
  archive: 'archived',
} as const;

type StaffRequest = { user: JwtPayloadType };

/// Admin panel plan, Phase C: messages, announcements, offers and the bell.
@ApiTags('Admin')
@ApiBearerAuth()
@Permit('notify.send')
@UseGuards(AuthGuard('jwt'), PermissionsGuard)
@Controller({ path: 'admin', version: '1' })
export class AdminCommsController {
  constructor(
    private readonly campaigns: AdminCampaignsService,
    private readonly announcements: AnnouncementsService,
    private readonly coupons: CouponsService,
    private readonly alerts: AdminAlertsService,
    private readonly totp: TotpService,
    private readonly audit: AuditService,
  ) {}

  @Get('campaigns/channels')
  channels(): Record<Channel, boolean> {
    return this.campaigns.channels();
  }

  @Post('campaigns/preview')
  @HttpCode(HttpStatus.OK)
  preview(@Body() dto: PreviewDto): Promise<{ count: number }> {
    return this.campaigns.preview(dto.segment, dto.content_class);
  }

  @Post('campaigns')
  create(
    @Body() dto: CampaignDto,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<CampaignView> {
    return this.campaigns.create(dto, actorOf(request, ip));
  }

  @Get('campaigns')
  list(): Promise<CampaignView[]> {
    return this.campaigns.list();
  }

  @Post('campaigns/:id/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(
    @Param('id') id: string,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<CampaignView> {
    return this.campaigns.cancel(id, actorOf(request, ip));
  }

  @Permit('content.manage')
  @Get('announcements')
  announcementList(): Promise<AnnouncementView[]> {
    return this.announcements.list();
  }

  @Permit('content.manage')
  @Post('announcements')
  createAnnouncement(
    @Body() dto: AnnouncementDto,
    @Request() request: StaffRequest,
  ): Promise<AnnouncementView> {
    return this.announcements.create(dto, Number(request.user.id));
  }

  @Permit('content.manage')
  @Patch('announcements/:id')
  updateAnnouncement(
    @Param('id') id: string,
    @Body() dto: AnnouncementDto,
  ): Promise<AnnouncementView> {
    return this.announcements.update(id, dto);
  }

  /// Publishing puts it in front of every matching user, so it is audited; so is taking it down.
  @Permit('content.manage')
  @Post('announcements/:id/:action')
  @HttpCode(HttpStatus.OK)
  async publish(
    @Param('id') id: string,
    @Param('action') action: string,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<AnnouncementView> {
    const status =
      ANNOUNCEMENT_ACTIONS[action as keyof typeof ANNOUNCEMENT_ACTIONS];
    if (!status) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: { code: 'UNKNOWN_ACTION', user_message: 'Unknown action.' },
      });
    }
    const done = await this.announcements.setStatus(id, status);
    await this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? ''),
      action: 'announcement_publish',
      resource: 'announcement',
      meta: { announcement_id: id, after: { status }, priority: done.priority },
      ip,
    });
    return done;
  }

  @Permit('content.manage')
  @Get('coupons/stats')
  offerStats(): Promise<OfferStats[]> {
    return this.coupons.stats();
  }

  @Permit('content.manage')
  @Patch('coupons/:code')
  async updateOffer(
    @Param('code') code: string,
    @Body() dto: OfferUpdateDto,
    @Headers('x-totp') totp: string | undefined,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<CouponView> {
    await this.totp.require(Number(request.user.id), totp ?? '');
    const updated = await this.coupons.update(code, dto);
    await this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? ''),
      action: 'coupon_update',
      resource: 'coupon',
      meta: JSON.parse(
        JSON.stringify({ code: updated.code, after: dto }),
      ) as Record<string, unknown>,
      ip,
    });
    return updated;
  }

  @Permit('panel.access')
  @Get('alerts')
  bell(@Request() request: StaffRequest): Promise<AdminAlert[]> {
    return this.alerts.for(request.user.role?.id);
  }
}

function actorOf(request: StaffRequest, ip: string): Actor {
  return {
    userId: Number(request.user.id),
    roleId: Number(request.user.role?.id),
    ip,
  };
}
