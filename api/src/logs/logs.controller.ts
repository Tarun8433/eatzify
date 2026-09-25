import {
  Body,
  Controller,
  DefaultValuePipe,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  LogsService,
  type DayView,
  type DiaryWindowView,
  type LogEntryView,
} from './logs.service';
import { LogFoodDto, PreviewFoodDto } from './dto/log-food.dto';
import type { NutritionView } from './nutrition-for';
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

  /// D-238. The add sheet's nutrition preview: what the chosen portion gives, nothing saved. A POST
  /// because the body names a food and a portion (api rule 6: no health data in a query string).
  @Post('food/preview')
  @HttpCode(HttpStatus.OK)
  public preview(@Body() dto: PreviewFoodDto): Promise<NutritionView> {
    return this.service.preview(dto);
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

  /// D-216. Windows for a backfill, so the phone never derives a 04:00 IST boundary (rule 8).
  /// `days` is a count, not health data, so a query string is fine here.
  @Get('windows')
  @HttpCode(HttpStatus.OK)
  public windows(
    @Query('days', new DefaultValuePipe(1), ParseIntPipe) days: number,
  ): { windows: DiaryWindowView[] } {
    return { windows: this.service.windows(days) };
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
