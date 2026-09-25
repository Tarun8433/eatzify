import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Post,
  Request,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiConsumes, ApiTags } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  Min,
} from 'class-validator';
import type { JwtPayloadType } from '../../auth/strategies/types/jwt-payload.type';
import type { RequestWithUser } from '../../utils/types/request-with-user.type';
import { MEAL_SLOTS } from '../../logs/dto/log-food.dto';
import type { LogEntryView } from '../../logs/logs.service';
import { FoodScanService, type ScanResult } from './food-scan.service';
import { ScanPolicyService, type ScanStatus } from './scan-policy.service';

/// A phone photo downscaled to 1024 px is well under this; anything bigger is not a meal photo.
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

class ScanFoodDto {
  /// Multipart fields arrive as text. `true` once the app's rewarded ad paid out (D-238).
  @IsOptional()
  @IsIn(['true', 'false'])
  ad_watched?: string;
}

/// D-240. "Yes" — which meal, and which of the scan's items to keep (all, when absent). Indexes,
/// never numbers: the nutrition comes from the stored estimate, summed by the server.
class ConfirmScanDto {
  @IsIn([...MEAL_SLOTS])
  slot: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(8)
  @IsInt({ each: true })
  @Min(0, { each: true })
  keep?: number[];
}

@ApiTags('Foods')
@ApiBearerAuth()
@Controller({ path: 'foods/scan', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class FoodScanController {
  constructor(
    private readonly scans: FoodScanService,
    private readonly policy: ScanPolicyService,
  ) {}

  /// Asked before the camera opens, so the app can say "2 scans left", ask for an ad, or show the
  /// upgrade sheet without the user taking a photo first.
  @Get('status')
  @HttpCode(HttpStatus.OK)
  status(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<ScanStatus> {
    return this.policy.status(Number(request.user.id));
  }

  /// The photo arrives in memory; it is written to the private store only if it holds food.
  @Post()
  @HttpCode(HttpStatus.OK)
  @ApiConsumes('multipart/form-data')
  @UseInterceptors(
    FileInterceptor('image', { limits: { fileSize: MAX_IMAGE_BYTES } }),
  )
  scan(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @UploadedFile() image: Express.Multer.File | undefined,
    @Body() body: ScanFoodDto,
  ): Promise<ScanResult> {
    return this.scans.scan(
      Number(request.user.id),
      image,
      body.ad_watched === 'true',
    );
  }

  @Post(':id/log')
  @HttpCode(HttpStatus.CREATED)
  confirm(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id', ParseIntPipe) id: number,
    @Body() body: ConfirmScanDto,
  ): Promise<LogEntryView> {
    return this.scans.confirm(
      Number(request.user.id),
      id,
      body.slot,
      body.keep,
    );
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  async discard(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id', ParseIntPipe) id: number,
  ): Promise<void> {
    await this.scans.discard(Number(request.user.id), id);
  }
}
