import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsIn, IsString, MaxLength } from 'class-validator';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import {
  AnnouncementsService,
  type AnnouncementView,
} from './announcements.service';
import { PushService } from './push.service';

class DeviceDto {
  @IsString()
  @MaxLength(512)
  token: string;

  @IsIn(['android', 'ios'])
  platform: 'android' | 'ios';
}

class UnregisterDto {
  @IsString()
  @MaxLength(512)
  token: string;
}

type Caller = { user: JwtPayloadType };

/// The app's side of Phase C: register a phone for push, read the announcements meant for you.
@ApiTags('Campaigns')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller({ version: '1' })
export class CampaignsController {
  constructor(
    private readonly push: PushService,
    private readonly announcements: AnnouncementsService,
    @InjectRepository(SubscriptionEntity)
    private readonly subscriptions: Repository<SubscriptionEntity>,
  ) {}

  @Post('devices')
  @HttpCode(HttpStatus.NO_CONTENT)
  register(@Request() req: Caller, @Body() dto: DeviceDto): Promise<void> {
    return this.push.register(Number(req.user.id), dto.token, dto.platform);
  }

  @Post('devices/unregister')
  @HttpCode(HttpStatus.NO_CONTENT)
  unregister(
    @Request() req: Caller,
    @Body() dto: UnregisterDto,
  ): Promise<void> {
    return this.push.unregister(Number(req.user.id), dto.token);
  }

  @Get('announcements')
  async active(@Request() req: Caller): Promise<AnnouncementView[]> {
    const now = new Date();
    const live = await this.subscriptions.findOne({
      where: {
        userId: Number(req.user.id),
        status: In(['trialing', 'active', 'grace']),
      },
      order: { startsAt: 'DESC' },
    });
    const paid =
      !!live &&
      live.tier !== 'FREE' &&
      (!live.currentPeriodEnd || live.currentPeriodEnd > now);
    return this.announcements.activeFor(paid, now);
  }
}
