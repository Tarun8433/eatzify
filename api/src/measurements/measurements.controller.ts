import {
  Body,
  Controller,
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
import {
  MeasurementsService,
  type BulkResultView,
  type HistoryView,
  type MeasurementView,
} from './measurements.service';
import { CreateMeasurementDto } from './dto/create-measurement.dto';
import { CreateMeasurementsBulkDto } from './dto/create-measurements-bulk.dto';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

@ApiTags('Measurements')
@ApiBearerAuth()
@Controller({ path: 'measurements', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class MeasurementsController {
  constructor(private readonly service: MeasurementsService) {}

  /// docs/09 §4.
  @Post()
  @HttpCode(HttpStatus.CREATED)
  public record(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: CreateMeasurementDto,
  ): Promise<{ measurement: MeasurementView; is_suspect: boolean }> {
    return this.service.record(Number(request.user.id), dto);
  }

  /// D-216. A health-platform sync — many readings, one request, one result per reading.
  @Post('bulk')
  @HttpCode(HttpStatus.OK)
  public recordMany(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: CreateMeasurementsBulkDto,
  ): Promise<{ results: BulkResultView[] }> {
    return this.service.recordMany(Number(request.user.id), dto.readings);
  }

  @Get(':kind')
  @HttpCode(HttpStatus.OK)
  public history(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('kind') kind: string,
  ): Promise<HistoryView> {
    return this.service.history(Number(request.user.id), kind);
  }
}
