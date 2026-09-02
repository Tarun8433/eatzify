import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { LogsService, type DayView, type LogEntryView } from './logs.service';
import { LogFoodDto } from './dto/log-food.dto';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

@ApiTags('Logs')
@ApiBearerAuth()
@Controller({ path: 'logs', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class LogsController {
  constructor(private readonly service: LogsService) {}

  /// docs/09 §5.
  @Post('food')
  @HttpCode(HttpStatus.CREATED)
  public logFood(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: LogFoodDto,
  ): Promise<LogEntryView> {
    return this.service.logFood(Number(request.user.id), dto);
  }

  /// `diary_date` is resolved server-side (docs/09 §5) — the client never computes the 04:00 IST
  /// boundary itself.
  @Get('day')
  @HttpCode(HttpStatus.OK)
  public day(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Query('date') date?: string,
  ): Promise<DayView> {
    return this.service.day(Number(request.user.id), date);
  }

  @Delete('food/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  public async remove(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id') id: string,
  ): Promise<void> {
    await this.service.remove(Number(request.user.id), id);
  }
}
