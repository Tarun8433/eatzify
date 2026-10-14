import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Ip,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import {
  OFFER_CHANNELS,
  type OfferChannel,
} from '../billing/entities/personal-offer.entity';
import {
  MAX_EXPIRY_DAYS,
  type PlayCatalogueOffer,
} from '../billing/offers/personal-offer-rules';
import {
  PersonalOffersService,
  type AdminOfferView,
} from '../billing/offers/personal-offers.service';
import { AuditService } from './audit.service';
import { Permit, PermissionsGuard } from './permissions.guard';

const TIERS = ['BASIC', 'PRO'] as const;
const DURATIONS = ['1M', '3M', '6M', '12M'] as const;
const PLAY_ID_MAX = 64;

class CreateOfferDto {
  @IsInt()
  @Min(1)
  user_id: number;

  @IsIn([...OFFER_CHANNELS])
  channel: OfferChannel;

  @IsIn([...TIERS])
  tier: (typeof TIERS)[number];

  @IsIn([...DURATIONS])
  duration: (typeof DURATIONS)[number];

  /// Cashfree only. Integer paise; the 1..normal-price bound is the service's (PriceService).
  @IsOptional()
  @IsInt()
  @Min(1)
  amount_paise?: number;

  @IsOptional()
  @IsString()
  @MaxLength(PLAY_ID_MAX)
  play_product_id?: string;

  @IsOptional()
  @IsString()
  @MaxLength(PLAY_ID_MAX)
  play_base_plan_id?: string;

  @IsOptional()
  @IsString()
  @MaxLength(PLAY_ID_MAX)
  play_offer_id?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(MAX_EXPIRY_DAYS)
  expires_in_days?: number;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}

class OffersQuery {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  user_id: number;
}

type StaffRequest = { user: JwtPayloadType };

/// D-265: personal offers — a special price for one person, sent to them as a link. Every write is
/// audited without the amount or anything personal: the offer id and the subject's user id only.
@ApiTags('Admin')
@ApiBearerAuth()
@Permit('offers.manage')
@UseGuards(AuthGuard('jwt'), PermissionsGuard)
@Controller({ path: 'admin/offers', version: '1' })
export class AdminOffersController {
  constructor(
    private readonly offers: PersonalOffersService,
    private readonly audit: AuditService,
  ) {}

  /// ACTIVE Play offers, read live from the Play Developer API. Empty when Play is not configured.
  @Get('play-catalog')
  playCatalog(): Promise<PlayCatalogueOffer[]> {
    return this.offers.playCatalog();
  }

  @Get()
  list(@Query() q: OffersQuery): Promise<AdminOfferView[]> {
    return this.offers.listFor(q.user_id, new Date());
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async create(
    @Body() dto: CreateOfferDto,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<AdminOfferView> {
    const created = await this.offers.create(
      {
        userId: dto.user_id,
        channel: dto.channel,
        tier: dto.tier,
        duration: dto.duration,
        amountPaise: dto.amount_paise,
        playProductId: dto.play_product_id,
        playBasePlanId: dto.play_base_plan_id,
        playOfferId: dto.play_offer_id,
        expiresInDays: dto.expires_in_days,
        note: dto.note ?? null,
      },
      Number(request.user.id),
      new Date(),
    );
    await this.record(request, ip, 'personal_offer_create', created);
    return created;
  }

  /// Idempotent: a second revoke answers with the offer as it already is.
  @Post(':id/revoke')
  @HttpCode(HttpStatus.OK)
  async revoke(
    @Param('id', ParseUUIDPipe) id: string,
    @Request() request: StaffRequest,
    @Ip() ip: string,
  ): Promise<AdminOfferView> {
    const revoked = await this.offers.revoke(id, new Date());
    await this.record(request, ip, 'personal_offer_revoke', revoked);
    return revoked;
  }

  private record(
    request: StaffRequest,
    ip: string,
    action: 'personal_offer_create' | 'personal_offer_revoke',
    offer: AdminOfferView,
  ): Promise<void> {
    return this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? ''),
      action,
      resource: 'personal_offer',
      subjectUserId: offer.user_id,
      meta: { offer_id: offer.id, channel: offer.channel },
      ip,
    });
  }
}
