import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { MessagesService, type MessageView } from './messages.service';
import type { AllConfigType } from '../config/config.type';

/// One room per conversation, named from the PAIR rather than from whoever opened it — the two
/// sides must end up in the same room whichever of them connected first.
export function roomFor(coachUserId: number, clientUserId: number): string {
  return `chat:${coachUserId}:${clientUserId}`;
}

/// What a socket sends: the id of the person on the other end, and what to say.
type Outgoing = { other_user_id?: number; body?: string };

/**
 * Live chat (docs/02 FR-5.5).
 *
 * The socket is a FASTER PATH, never a second set of rules: joining a room and sending a message
 * both go through `MessagesService`, which re-checks the client's `chat` grant every time
 * (docs/10 §3). A socket that was let into a room yesterday proves nothing today.
 *
 * `mine` is deliberately absent from what is broadcast: the same message is "mine" to one side and
 * not to the other, so the payload carries `sender_user_id` and each end decides for itself.
 */
@WebSocketGateway({ namespace: '/chat', cors: { origin: '*' } })
export class ChatGateway implements OnGatewayConnection {
  private readonly log = new Logger(ChatGateway.name);

  @WebSocketServer()
  server: Server;

  constructor(
    private readonly messages: MessagesService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService<AllConfigType>,
  ) {}

  /// The token travels in the handshake, never in a query string: a URL ends up in proxy logs and
  /// this one would carry a session.
  handleConnection(socket: Socket): void {
    const token =
      (socket.handshake.auth?.token as string | undefined) ??
      socket.handshake.headers.authorization?.replace('Bearer ', '');

    try {
      const payload = this.jwt.verify<{ id: number | string }>(token ?? '', {
        secret: this.config.getOrThrow('auth.secret', { infer: true }),
      });
      socket.data.userId = Number(payload.id);
    } catch {
      // No id, no rooms. Nothing is logged about the attempt beyond the fact of it (rule 5).
      this.log.warn('chat socket refused: unusable token');
      socket.disconnect(true);
    }
  }

  @SubscribeMessage('join')
  async join(
    @ConnectedSocket() socket: Socket,
    @MessageBody() data: Outgoing,
  ): Promise<{ joined: boolean }> {
    const userId = socket.data.userId as number | undefined;
    if (!userId || !data?.other_user_id) return { joined: false };

    try {
      const pair = await this.messages.pairFor(
        userId,
        data.other_user_id,
        new Date(),
      );
      await socket.join(roomFor(pair.coachUserId, pair.clientUserId));
      return { joined: true };
    } catch {
      // The grant is gone, or there never was one. The socket stays connected and in no room.
      return { joined: false };
    }
  }

  @SubscribeMessage('send')
  async send(
    @ConnectedSocket() socket: Socket,
    @MessageBody() data: Outgoing,
  ): Promise<{ sent: boolean }> {
    const userId = socket.data.userId as number | undefined;
    if (!userId || !data?.other_user_id || !data.body) return { sent: false };

    try {
      const pair = await this.messages.pairFor(
        userId,
        data.other_user_id,
        new Date(),
      );
      const saved = await this.messages.send(
        userId,
        data.other_user_id,
        data.body,
        new Date(),
      );
      this.publish(pair.coachUserId, pair.clientUserId, saved);
      return { sent: true };
    } catch {
      return { sent: false };
    }
  }

  /// Also called by the REST route, so a message sent over HTTP still arrives live for whoever has
  /// the thread open.
  publish(
    coachUserId: number,
    clientUserId: number,
    message: MessageView,
  ): void {
    this.server
      ?.to(roomFor(coachUserId, clientUserId))
      .emit('message', { ...message, mine: undefined });
  }
}
