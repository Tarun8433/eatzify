import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Patch,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  ProfileService,
  OnboardingResult,
  ProfileView,
  HealthProfileView,
} from './profile.service';
import { OnboardingDto } from './dto/onboarding.dto';
import { PatchHealthDto } from './dto/patch-health.dto';
import { PatchProfileDto } from './dto/patch-profile.dto';
import { UsersService } from '../users/users.service';
import { ProfileAuditService } from './profile-audit.service';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

@ApiTags('Profile')
@ApiBearerAuth()
@Controller({ path: 'profile', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class ProfileController {
  constructor(
    private readonly service: ProfileService,
    private readonly users: UsersService,
    private readonly audit: ProfileAuditService,
  ) {}

  /// docs/09 §4. The user id comes from the token, never from the body — a client must not be able
  /// to write someone else's health profile.
  @Post('onboarding')
  @HttpCode(HttpStatus.CREATED)
  public onboarding(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: OnboardingDto,
  ): Promise<OnboardingResult> {
    return this.service.onboard(Number(request.user.id), dto);
  }

  /// docs/09 §4.
  @Get()
  @HttpCode(HttpStatus.OK)
  public async profile(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<ProfileView> {
    const userId = Number(request.user.id);
    // The photo lives on the user, not the profile — it is set through PATCH /auth/me, which the
    // boilerplate already owns. Reading it here keeps the client to one request for the You tab.
    const user = await this.users.findById(userId);
    return this.service.getProfile(userId, user?.photo?.path ?? null);
  }

  /// docs/09 §4 — edits the profile half; re-gates if anthropometrics changed.
  @Patch()
  @HttpCode(HttpStatus.OK)
  public patchProfile(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: PatchProfileDto,
  ) {
    return this.service.patchProfile(Number(request.user.id), dto);
  }

  /// docs/09 §4 — writes a new health-profile version and returns it.
  /// The change history for the signed-in user. docs/13 §"right of access": a user may ask what
  /// you hold about them, and "everything you ever typed" is part of that answer.
  ///
  /// Scoped to the caller. A coach or admin reading somebody else's history is a different endpoint
  /// behind the docs/10 RBAC matrix, and must not be an optional query parameter on this one.
  @Get('history')
  @HttpCode(HttpStatus.OK)
  public history(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Query('field') field?: string,
    @Query('limit') limit?: string,
  ) {
    return this.audit.history(Number(request.user.id), {
      field,
      limit: limit === undefined ? undefined : Number(limit),
    });
  }

  @Patch('health')
  @HttpCode(HttpStatus.OK)
  public patchHealth(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: PatchHealthDto,
  ): Promise<HealthProfileView> {
    return this.service.patchHealth(Number(request.user.id), dto);
  }
}
