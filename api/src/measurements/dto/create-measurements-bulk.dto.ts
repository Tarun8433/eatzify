import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsBoolean,
  IsOptional,
  ValidateNested,
} from 'class-validator';
import { CreateMeasurementDto } from './create-measurement.dto';

/// Enough for a 30-day backfill of every synced metric, with room to add one or two more before this
/// needs to move. A phone sending more than this is a bug, not a user.
export const MAX_BULK_READINGS = 200;

/// One synced reading.
export class BulkReadingDto extends CreateMeasurementDto {
  /// D-218. The person asked for this device figure — a tap on Sync or Connect — so it may replace
  /// a figure they typed that day. Absent on every background sync, which never does.
  @ApiPropertyOptional({ example: false })
  @IsOptional()
  @IsBoolean()
  replace_manual?: boolean;
}

/// D-214. Many readings in one request — a health-platform sync, not a person typing.
export class CreateMeasurementsBulkDto {
  @ApiProperty({ type: [BulkReadingDto] })
  @ArrayMinSize(1)
  @ArrayMaxSize(MAX_BULK_READINGS)
  @ValidateNested({ each: true })
  @Type(() => BulkReadingDto)
  readings: BulkReadingDto[];
}
