import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  ParseUUIDPipe,
  Post,
  Query,
  Request,
  UnprocessableEntityException,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import {
  CoachApplicationService,
  type CoachApplicationView,
} from './coach-application.service';
import { CoachGrantService, type GrantView } from './coach-grant.service';
import {
  CheckInsService,
  MAX_ACTIONS,
  MAX_ACTION_LENGTH,
  MAX_NOTE_LENGTH,
  type AlertView,
  type CheckInView,
} from './check-ins.service';
import { CHECK_IN_STATUSES, type CheckInStatus } from './check-in-rules';
import {
  MAX_MESSAGE_LENGTH,
  MessagesService,
  type MessageView,
  type ThreadView,
} from './messages.service';
import { ChatGateway } from './chat.gateway';
import {
  CoachInviteService,
  SentInviteView,
  type InviteView,
} from './coach-invite.service';
import {
  CoachClientsService,
  type CoachDashboard,
} from './coach-clients.service';
import type { ClientDetailView, RosterRow } from './client-view.serializer';
import {
  CoachProgressService,
  type ClientDiaryView,
  type ClientProgressView,
} from './coach-progress.service';
import type { CoachDiscipline } from './entities/coach-application.entity';
import { COACH_DISCIPLINES } from './entities/coach-application.entity';
import type { GrantScope } from './entities/coach-grant.entity';
import { GRANT_SCOPES } from './entities/coach-grant.entity';
import { UsersService } from '../users/users.service';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';

/// docs/12 §6's coaching agreement (D-235). Which version was shown — the same reason as the first.
class AcceptCoachingAgreementDto {
  @IsString()
  agreement_version: string;
}

class AcceptAgreementDto {
  /// Which version was shown. "They agreed" is only evidence if it says to what (docs/12 §6).
  @IsString()
  agreement_version: string;

  /// What the applicant says they are. Optional, because the column is new and an app that has not
  /// shipped the question yet must still be able to apply — an old client is not a bad request.
  /// Self-declared and never treated as more: `verifiedAttributes` is what a human confirmed.
  @IsOptional()
  @IsIn([...COACH_DISCIPLINES])
  discipline?: CoachDiscipline;
}

class InviteClientDto {
  /// E.164, as docs/09 §6 names it. Never normalised here — a number the coach cannot recognise
  /// back is a number they cannot tell they mistyped.
  @IsString()
  phone_e164: string;

  /// What the coach is ASKING for. Capped by their level before the row is written.
  @IsArray()
  @IsIn([...GRANT_SCOPES], { each: true })
  scopes: GrantScope[];
}

class SetDisciplineDto {
  /// A closed list with a DB CHECK behind it. Free text would make the one question this field
  /// exists to answer — how many of each kind of partner there are — unanswerable.
  @IsIn([...COACH_DISCIPLINES])
  discipline: CoachDiscipline;
}

class AttachDocumentsDto {
  @IsOptional()
  @IsUUID()
  id_document_file_id?: string;

  @IsOptional()
  @IsUUID()
  qualification_document_file_id?: string;
}

/// docs/09 §6: `POST /coach/messages { client_id, body }`.
///
/// The doc names the field from the coach's side; the same endpoint carries the client's replies,
/// so `other_user_id` is accepted as well and means the same thing (D-226).
class SendMessageDto {
  @IsOptional()
  @IsInt()
  client_id?: number;

  @IsOptional()
  @IsInt()
  other_user_id?: number;

  @IsString()
  @MaxLength(MAX_MESSAGE_LENGTH)
  body: string;
}

/// docs/09 §6: what the coach writes when they close a week's review.
class CompleteCheckInDto {
  @IsOptional()
  @IsString()
  @MaxLength(MAX_NOTE_LENGTH)
  notes?: string;

  /// What the two of them agreed to do next — short lines, capped so the field stays a list.
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  @MaxLength(MAX_ACTION_LENGTH, { each: true })
  @ArrayMaxSize(MAX_ACTIONS)
  actions?: string[];
}

/**
 * Coach onboarding, docs/12 §6. Applying to be a partner and checking where that application got
 * to — nothing about a client, because an applicant has none.
 *
 * The route this controller cannot reach is verification: `POST /admin/coaches/{id}/verify`
 * (docs/09 §9) belongs to an admin and is E8. An applicant may take themselves to level 1 and
 * hand their documents to a human, and that is the whole of what self-service should be able to do.
 */
@ApiTags('Coach')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller({ path: 'coach', version: '1' })
export class CoachController {
  constructor(
    private readonly applications: CoachApplicationService,
    private readonly grants: CoachGrantService,
    private readonly invites: CoachInviteService,
    private readonly clients: CoachClientsService,
    private readonly progress: CoachProgressService,
    private readonly checkins: CheckInsService,
    private readonly messages: MessagesService,
    private readonly chat: ChatGateway,
    private readonly users: UsersService,
  ) {}

  /// docs/09 §6. The coach asks; the client answers.
  ///
  /// 204 whatever happens to the number — docs/09 §3: "never return whether a number exists." A
  /// response that differed would turn this into a way to enumerate who is on the app.
  @Post('clients/invite')
  @HttpCode(HttpStatus.NO_CONTENT)
  async invite(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: InviteClientDto,
  ): Promise<void> {
    await this.invites.invite({
      coachUserId: Number(request.user.id),
      phoneE164: dto.phone_e164,
      scopes: dto.scopes,
      now: new Date(),
    });
  }

  /// What this client has been asked. Keyed on the caller's OWN number, from their token — an
  /// invite list that took a number as input would answer questions about other people.
  @Get('invites')
  @HttpCode(HttpStatus.OK)
  async myInvites(
    @Request() request: { user: JwtPayloadType & { phone?: string } },
  ): Promise<InviteView[]> {
    const phone = await this.phoneOf(Number(request.user.id));
    return phone ? this.invites.pendingFor(phone, new Date()) : [];
  }

  /**
   * What THIS coach has asked, for their own Clients screen.
   *
   * Carries the invited person's name and photo when the number belongs to an account. Their
   * presence therefore reveals that the number is registered — which docs/09 §3 forbids the invite
   * endpoint itself from doing. Taken deliberately as a product decision; see DECISIONS.md. The
   * ask stays an ask: nothing here grants the coach any of the client's data.
   */
  @Get('invites/sent')
  @HttpCode(HttpStatus.OK)
  async sentInvites(
    @Request() request: { user: JwtPayloadType },
  ): Promise<SentInviteView[]> {
    return this.invites.sentBy(Number(request.user.id), new Date());
  }

  /// The client says yes. The only thing in the system that turns an ask into access.
  @Post('invites/:id/accept')
  @HttpCode(HttpStatus.NO_CONTENT)
  async acceptInvite(
    @Request() request: { user: JwtPayloadType },
    @Param('id') id: string,
  ): Promise<void> {
    const userId = Number(request.user.id);
    const phone = await this.phoneOf(userId);

    await this.invites.accept({
      inviteId: id,
      clientUserId: userId,
      clientPhoneE164: phone ?? '',
      now: new Date(),
    });
  }

  @Post('invites/:id/decline')
  @HttpCode(HttpStatus.NO_CONTENT)
  async declineInvite(
    @Request() request: { user: JwtPayloadType },
    @Param('id') id: string,
  ): Promise<void> {
    await this.invites.decline({
      inviteId: id,
      clientPhoneE164: (await this.phoneOf(Number(request.user.id))) ?? '',
      now: new Date(),
    });
  }

  /// docs/10 §3's "Who can see my data" screen, from the CLIENT's side.
  ///
  /// Paused rows are included on purpose: what access used to exist is part of the answer, and a
  /// list that quietly forgets a revoked coach cannot be audited by the person it belongs to.
  @Get('access')
  @HttpCode(HttpStatus.OK)
  access(@Request() request: { user: JwtPayloadType }): Promise<GrantView[]> {
    return this.grants.forClient(Number(request.user.id));
  }

  /// One tap, effective immediately (docs/10 §3). No confirmation step and no reason field —
  /// asking someone to justify taking back their own health data is the retention dark pattern
  /// that section forbids.
  ///
  /// The client id comes from the token. A body-supplied one would let anyone revoke anyone's
  /// grants, or worse, grant them.
  @Post('access/:coachUserId/revoke')
  @HttpCode(HttpStatus.NO_CONTENT)
  async revoke(
    @Request() request: { user: JwtPayloadType },
    @Param('coachUserId', ParseIntPipe) coachUserId: number,
  ): Promise<void> {
    await this.grants.revoke(
      Number(request.user.id),
      coachUserId,
      // The clock lives at the edge: the service is given a time rather than reading one, so its
      // expiry rules can be tested without waiting for them.
      new Date(),
    );
  }

  /// The caller's own number, for matching invites addressed to it. An empty string when the
  /// account has none — every invite lookup then finds nothing, which is the correct answer for
  /// an account no invite could have been addressed to.
  private async phoneOf(userId: number): Promise<string | null> {
    const user = await this.users.findById(userId);
    return user?.phone ?? null;
  }

  /**
   * Who this coach is working with, docs/10 §1.
   *
   * Driven by the GRANTS, not by a role: a coach with no grant has an empty roster whatever their
   * level, and nothing here can be reached by being promoted.
   */
  @Get('clients')
  @HttpCode(HttpStatus.OK)
  roster(@Request() request: { user: JwtPayloadType }): Promise<RosterRow[]> {
    return this.clients.roster(Number(request.user.id), new Date());
  }

  /// docs/12 §9's coach widgets: counts, renewals due, and the at-risk list. One call, because a
  /// tile and the list under it must never disagree.
  @Get('dashboard')
  @HttpCode(HttpStatus.OK)
  dashboard(
    @Request() request: { user: JwtPayloadType },
  ): Promise<CoachDashboard> {
    return this.clients.dashboard(Number(request.user.id), new Date());
  }

  /// One client, filtered to what they allowed. A 404 rather than a 403 when there is no grant —
  /// "not allowed" confirms the person exists, and this id space must not answer that.
  @Get('clients/:clientUserId')
  @HttpCode(HttpStatus.OK)
  client(
    @Request() request: { user: JwtPayloadType },
    @Param('clientUserId', ParseIntPipe) clientUserId: number,
  ): Promise<ClientDetailView> {
    return this.clients.client(
      Number(request.user.id),
      clientUserId,
      new Date(),
    );
  }

  /**
   * What this client has actually logged — weight, steps, water, and how regularly.
   *
   * docs/10 §3's `progress` scope in full. Those series were already granted and simply were not
   * being read back, so a coach whose client had shared everything saw five profile fields.
   */
  @Get('clients/:clientUserId/progress')
  @HttpCode(HttpStatus.OK)
  clientProgress(
    @Request() request: { user: JwtPayloadType },
    @Param('clientUserId', ParseIntPipe) clientUserId: number,
  ): Promise<ClientProgressView> {
    return this.progress.progress(
      Number(request.user.id),
      clientUserId,
      new Date(),
    );
  }

  /// One day of the client's food diary. Coaching partners only — docs/10 §2 gives coach_l2 an
  /// adherence percentage and coach_l3 the logs themselves.
  @Get('clients/:clientUserId/diary')
  @HttpCode(HttpStatus.OK)
  clientDiary(
    @Request() request: { user: JwtPayloadType },
    @Param('clientUserId', ParseIntPipe) clientUserId: number,
    @Query('date') date?: string,
  ): Promise<ClientDiaryView> {
    // Passed through as undefined, never as an empty string. `LogsService.day` defaults with `??`,
    // which does not catch `''` — so an empty string reached Postgres as a date and took the whole
    // request down with it.
    return this.progress.diary(
      Number(request.user.id),
      clientUserId,
      date,
      new Date(),
    );
  }

  /// docs/09 §6: `GET /coach/checkins?status=due`. The queue is built as it is read, so a coach
  /// who has just been granted access sees this week's review rather than an empty tab.
  @Get('checkins')
  @HttpCode(HttpStatus.OK)
  checkIns(
    @Request() request: { user: JwtPayloadType },
    @Query('status') status?: string,
  ): Promise<CheckInView[]> {
    const wanted = (CHECK_IN_STATUSES as readonly string[]).includes(
      status ?? '',
    )
      ? (status as CheckInStatus)
      : undefined;

    return this.checkins.queue(Number(request.user.id), new Date(), wanted);
  }

  /// docs/09 §6: `POST /coach/checkins/{id}/complete { notes, actions[] }`.
  @Post('checkins/:id/complete')
  @HttpCode(HttpStatus.OK)
  completeCheckIn(
    @Request() request: { user: JwtPayloadType },
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CompleteCheckInDto,
  ): Promise<CheckInView> {
    return this.checkins.complete(
      Number(request.user.id),
      id,
      { notes: dto.notes, actions: dto.actions },
      new Date(),
    );
  }

  /// docs/09 §6: `GET /coach/alerts` — no-log ≥3d, off-trend, expiring, missed check-in.
  @Get('alerts')
  @HttpCode(HttpStatus.OK)
  alerts(@Request() request: { user: JwtPayloadType }): Promise<AlertView[]> {
    return this.checkins.alerts(Number(request.user.id), new Date());
  }

  /// Who the caller can talk to: their clients, or their coach. docs/02 FR-5.5.
  @Get('threads')
  @HttpCode(HttpStatus.OK)
  threads(@Request() request: { user: JwtPayloadType }): Promise<ThreadView[]> {
    return this.messages.threads(Number(request.user.id), new Date());
  }

  /// One conversation, newest first. `before` pages backwards; neither is health data, so both may
  /// ride in the query string (api rule 6).
  @Get('messages/:otherUserId')
  @HttpCode(HttpStatus.OK)
  messageHistory(
    @Request() request: { user: JwtPayloadType },
    @Param('otherUserId', ParseIntPipe) otherUserId: number,
    @Query('before') before?: string,
  ): Promise<MessageView[]> {
    return this.messages.history(
      Number(request.user.id),
      otherUserId,
      new Date(),
      { before },
    );
  }

  /// docs/09 §6: `POST /coach/messages`.
  @Post('messages')
  @HttpCode(HttpStatus.CREATED)
  sendMessage(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: SendMessageDto,
  ): Promise<MessageView> {
    const otherUserId = dto.client_id ?? dto.other_user_id;
    if (otherUserId === undefined) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'RECIPIENT_REQUIRED',
          user_message: 'We could not tell who this message is for.',
        },
      });
    }

    return this.sendAndPublish(Number(request.user.id), otherUserId, dto.body);
  }

  /// The socket is the fast path, not a different one: a message posted over HTTP still lands live
  /// for whoever has the thread open.
  private async sendAndPublish(
    userId: number,
    otherUserId: number,
    body: string,
  ): Promise<MessageView> {
    const now = new Date();
    const pair = await this.messages.pairFor(userId, otherUserId, now);
    const saved = await this.messages.send(userId, otherUserId, body, now);

    this.chat.publish(pair.coachUserId, pair.clientUserId, saved);
    return saved;
  }

  /// The reader has seen this thread.
  @Post('messages/:otherUserId/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  readMessages(
    @Request() request: { user: JwtPayloadType },
    @Param('otherUserId', ParseIntPipe) otherUserId: number,
  ): Promise<void> {
    return this.messages.markRead(
      Number(request.user.id),
      otherUserId,
      new Date(),
    );
  }

  @Get('application')
  @HttpCode(HttpStatus.OK)
  current(
    @Request() request: { user: JwtPayloadType },
  ): Promise<CoachApplicationView | null> {
    return this.applications.current(Number(request.user.id));
  }

  /// What the applicant says they do, and the only step they may revise. Comes BEFORE the
  /// agreement because it is the first thing the partner screen asks.
  @Post('application/discipline')
  @HttpCode(HttpStatus.OK)
  setDiscipline(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: SetDisciplineDto,
  ): Promise<CoachApplicationView> {
    return this.applications.setDiscipline(
      Number(request.user.id),
      dto.discipline,
    );
  }

  /// docs/12 §6: level 1 is "signup + agreement". This is that, and it is the only step that
  /// grants a role without a human in the loop.
  @Post('application/agreement')
  @HttpCode(HttpStatus.OK)
  accept(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: AcceptAgreementDto,
  ): Promise<CoachApplicationView> {
    return this.applications.acceptAgreement(
      Number(request.user.id),
      dto.agreement_version,
      dto.discipline,
    );
  }

  /// docs/12 §6: level 3's partner half. A verified partner accepts it; a client's grant completes
  /// it, and whichever lands second is what promotes (D-235).
  @Post('application/coaching-agreement')
  @HttpCode(HttpStatus.OK)
  acceptCoaching(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: AcceptCoachingAgreementDto,
  ): Promise<CoachApplicationView> {
    return this.applications.acceptCoachingAgreement(
      Number(request.user.id),
      dto.agreement_version,
    );
  }

  /// File ids, uploaded through the files module. The documents never travel through this route.
  @Post('application/documents')
  @HttpCode(HttpStatus.OK)
  attach(
    @Request() request: { user: JwtPayloadType },
    @Body() dto: AttachDocumentsDto,
  ): Promise<CoachApplicationView> {
    return this.applications.attachDocuments(Number(request.user.id), {
      idDocumentFileId: dto.id_document_file_id,
      qualificationDocumentFileId: dto.qualification_document_file_id,
    });
  }

  @Post('application/submit')
  @HttpCode(HttpStatus.OK)
  submit(
    @Request() request: { user: JwtPayloadType },
  ): Promise<CoachApplicationView> {
    return this.applications.submit(Number(request.user.id));
  }
}
