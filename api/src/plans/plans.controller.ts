import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  HttpStatus,
  Post,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { PlansService, type PlanResponse } from './plans.service';
import { GeneratePlanDto } from './dto/generate-plan.dto';
import { diaryDateFor } from './diary-date';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

@ApiTags('Plans')
@ApiBearerAuth()
@Controller({ path: 'plans', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class PlansController {
  constructor(private readonly service: PlansService) {}

  /// docs/09 §4.2.
  @Post('generate')
  @HttpCode(HttpStatus.CREATED)
  public generate(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: GeneratePlanDto,
    @Headers('Idempotency-Key') idempotencyKey?: string,
  ): Promise<PlanResponse> {
    return this.service.generate(
      Number(request.user.id),
      // CLAUDE.md rule 8: the server owns the diary day. The client never sends a date.
      diaryDateFor(new Date()),
      dto.regenerate_reason ?? null,
      idempotencyKey ?? null,
    );
  }

  /// The current plan, or null when none has been generated.
  /// The foods this user may choose from (D-82). Not the plan's contents — see PlanOptionsService.
  @Get('options')
  @HttpCode(HttpStatus.OK)
  public options(@Request() request: RequestWithUser<JwtPayloadType>) {
    return this.service.options(Number(request.user.id));
  }

  @Get('current')
  @HttpCode(HttpStatus.OK)
  public current(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<PlanResponse | null> {
    return this.service.latest(Number(request.user.id));
  }
}
