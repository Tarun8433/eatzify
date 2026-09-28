import {
  Controller,
  DefaultValuePipe,
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
  MAX_NOTIFICATIONS,
  NotificationsService,
  type NotificationListView,
} from './notifications.service';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

/// The reader's own messages. Nothing here is health data, so a count and a cursor may ride in the
/// query string (api rule 6).
@ApiTags('Notifications')
@ApiBearerAuth()
@Controller({ path: 'notifications', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class NotificationsController {
  constructor(private readonly service: NotificationsService) {}

  @Get()
  @HttpCode(HttpStatus.OK)
  public list(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Query('limit', new DefaultValuePipe(MAX_NOTIFICATIONS), ParseIntPipe)
    limit: number,
    @Query('before') before?: string,
  ): Promise<NotificationListView> {
    return this.service.list(Number(request.user.id), { limit, before });
  }

  @Post(':id/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  public read(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id') id: string,
  ): Promise<void> {
    return this.service.markRead(Number(request.user.id), id);
  }

  @Post('read-all')
  @HttpCode(HttpStatus.NO_CONTENT)
  public readAll(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<void> {
    return this.service.markAllRead(Number(request.user.id));
  }
}
