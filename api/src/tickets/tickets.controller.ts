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
import { IsOptional, IsString } from 'class-validator';
import {
  TicketsService,
  type TicketRow,
  type TicketThread,
} from './tickets.service';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

class OpenTicketDto {
  @IsString()
  subject: string;

  @IsString()
  body: string;

  /// docs/09 §1: every response carries an `X-Request-Id` and "support tickets quote it". The app
  /// puts the id of the response that went wrong here, so the logs for that moment can be found.
  @IsOptional()
  @IsString()
  request_id?: string;
}

class ReplyDto {
  @IsString()
  body: string;
}

/// docs/14 §6's "help/tickets" screen, from the user's side. The same rows the admin surface reads
/// (docs/09 §9) — one conversation, two directions.
@ApiTags('Tickets')
@ApiBearerAuth()
@Controller({ path: 'tickets', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class TicketsController {
  constructor(private readonly tickets: TicketsService) {}

  @Get()
  list(
    @Request() request: RequestWithUser<JwtPayloadType>,
  ): Promise<TicketRow[]> {
    return this.tickets.mine(Number(request.user.id));
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  open(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Body() dto: OpenTicketDto,
  ): Promise<TicketRow> {
    return this.tickets.open(Number(request.user.id), {
      subject: dto.subject,
      body: dto.body,
      requestId: dto.request_id ?? null,
    });
  }

  @Get(':id')
  thread(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id') id: string,
  ): Promise<TicketThread> {
    return this.tickets.thread(id, {
      userId: Number(request.user.id),
      isSupport: false,
    });
  }

  @Post(':id/reply')
  @HttpCode(HttpStatus.OK)
  reply(
    @Request() request: RequestWithUser<JwtPayloadType>,
    @Param('id') id: string,
    @Body() dto: ReplyDto,
  ): Promise<TicketRow> {
    return this.tickets.reply(
      id,
      { userId: Number(request.user.id), isSupport: false },
      dto.body,
    );
  }
}
