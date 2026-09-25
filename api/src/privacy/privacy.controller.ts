import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsBoolean, IsIn, IsOptional, IsString } from 'class-validator';
import {
  CONSENT_TYPES,
  PrivacyService,
  type ConsentType,
  type ConsentView,
  type PrivacyRequestView,
} from './privacy.service';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

class ConsentDto {
  @IsIn([...CONSENT_TYPES])
  type: ConsentType;

  @IsBoolean()
  granted: boolean;

  /// docs/13 §3: the notice version the person agreed to is stored with the row. "They agreed" is
  /// only evidence if it says to what.
  @IsOptional()
  @IsString()
  policy_version?: string;
}

/**
 * docs/13 §9's data-subject rights, and §3's consent withdrawal — the "Privacy & data" screen's
 * whole backend.
 *
 * Every route is scoped to the caller. There is deliberately no `userId` parameter anywhere here:
 * an endpoint that erases an account named in a body is one authorisation bug away from erasing
 * somebody else's.
 */
@ApiTags('Privacy')
@ApiBearerAuth()
@Controller({ path: 'privacy', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class PrivacyController {
  constructor(private readonly privacy: PrivacyService) {}

  @Get('consents')
  consents(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<ConsentView[]> {
    return this.privacy.consents(Number(request.user.id));
  }

  /// Withdrawal is as easy as granting (docs/13 §3): the same route, with `granted: false`.
  @Post('consents')
  @HttpCode(HttpStatus.OK)
  setConsent(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: ConsentDto,
  ): Promise<ConsentView[]> {
    return this.privacy.setConsent(
      Number(request.user.id),
      dto.type,
      dto.granted,
      dto.policy_version,
    );
  }

  /// What has been asked for, and where it got to.
  @Get('requests')
  requests(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<PrivacyRequestView[]> {
    return this.privacy.open(Number(request.user.id));
  }

  /// docs/13 §9: `POST /privacy/export`. The link expires in 24 hours.
  @Post('export')
  @HttpCode(HttpStatus.OK)
  requestExport(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<PrivacyRequestView> {
    return this.privacy.requestExport(Number(request.user.id));
  }

  /// The bundle. Streamed to the person it belongs to, never to a URL somebody can forward.
  @Get('export/:id')
  bundle(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id') id: string,
  ): Promise<Record<string, unknown>> {
    return this.privacy.bundleFor(Number(request.user.id), id);
  }

  /// docs/13 §9: `POST /privacy/delete` — seven days' cooling-off, then it runs.
  @Post('delete')
  @HttpCode(HttpStatus.ACCEPTED)
  requestDelete(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<PrivacyRequestView> {
    return this.privacy.requestDelete(Number(request.user.id));
  }

  /// Changed their mind. Nothing was removed.
  @Delete('delete')
  @HttpCode(HttpStatus.NO_CONTENT)
  cancelDelete(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<void> {
    return this.privacy.cancelDelete(Number(request.user.id));
  }
}
