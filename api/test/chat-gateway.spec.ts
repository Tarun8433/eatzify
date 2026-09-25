import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { Socket } from 'socket.io';
import { ChatGateway, roomFor } from '../src/coach/chat.gateway';
import {
  MessagesService,
  type MessageView,
} from '../src/coach/messages.service';

/// docs/02 FR-5.5. The socket is a faster path to the same rules — every join and every send is
/// re-checked against the client's `chat` grant (docs/10 §3).

const COACH = 1;
const CLIENT = 7;

const message: MessageView = {
  id: 'm1',
  mine: true,
  sender_user_id: COACH,
  body: 'How was the week?',
  read_at: null,
  created_at: '2026-09-18T10:00:00.000Z',
};

function gatewayWith({ allowed = true }: { allowed?: boolean } = {}) {
  const joined: string[] = [];
  const emitted: { room: string; payload: Record<string, unknown> }[] = [];
  const sentBodies: string[] = [];

  const messages = {
    pairFor: () => {
      if (!allowed) throw new Error('CHAT_NOT_ALLOWED');
      return Promise.resolve({
        coachUserId: COACH,
        clientUserId: CLIENT,
        iAmCoach: true,
      });
    },
    send: (_: number, __: number, body: string) => {
      sentBodies.push(body);
      return Promise.resolve({ ...message, body });
    },
  } as unknown as MessagesService;

  const jwt = {
    verify: (token: string) => {
      if (token !== 'good') throw new Error('bad token');
      return { id: COACH };
    },
  } as unknown as JwtService;

  const config = { getOrThrow: () => 'secret' } as unknown as ConfigService;

  const gateway = new ChatGateway(messages, jwt, config as never);
  gateway.server = {
    to: (room: string) => ({
      emit: (_: string, payload: Record<string, unknown>) =>
        emitted.push({ room, payload }),
    }),
  } as never;

  const socket = (token: string | undefined, userId?: number) =>
    ({
      handshake: { auth: token ? { token } : {}, headers: {} },
      data: userId === undefined ? {} : { userId },
      join: (room: string) => {
        joined.push(room);
        return Promise.resolve();
      },
      disconnect: () => {
        (socket as unknown as { disconnected?: boolean }).disconnected = true;
      },
    }) as unknown as Socket;

  return { gateway, socket, joined, emitted, sentBodies };
}

describe('connecting', () => {
  it('should read the caller from the token in the handshake', () => {
    const { gateway, socket } = gatewayWith();
    const client = socket('good');

    gateway.handleConnection(client);

    expect(client.data.userId).toBe(COACH);
  });

  it('should drop a socket with an unusable token', () => {
    const { gateway, socket } = gatewayWith();
    const client = socket('rubbish');
    let dropped = false;
    client.disconnect = (() => {
      dropped = true;
    }) as never;

    gateway.handleConnection(client);

    expect(dropped).toBe(true);
    expect(client.data.userId).toBeUndefined();
  });
});

describe('joining a thread', () => {
  it('should put both sides in the same room, named from the pair', async () => {
    const { gateway, socket, joined } = gatewayWith();

    const answer = await gateway.join(socket('good', COACH), {
      other_user_id: CLIENT,
    });

    expect(answer.joined).toBe(true);
    expect(joined).toEqual([roomFor(COACH, CLIENT)]);
  });

  it('should refuse a room the grant no longer allows', async () => {
    const { gateway, socket, joined } = gatewayWith({ allowed: false });

    const answer = await gateway.join(socket('good', COACH), {
      other_user_id: CLIENT,
    });

    expect(answer.joined).toBe(false);
    expect(joined).toEqual([]);
  });

  it('should refuse a socket that never authenticated', async () => {
    const { gateway, socket, joined } = gatewayWith();

    expect(
      await gateway.join(socket(undefined), { other_user_id: CLIENT }),
    ).toEqual({
      joined: false,
    });
    expect(joined).toEqual([]);
  });
});

describe('sending over the socket', () => {
  it('should store the message and broadcast it to the room', async () => {
    const { gateway, socket, emitted, sentBodies } = gatewayWith();

    const answer = await gateway.send(socket('good', COACH), {
      other_user_id: CLIENT,
      body: 'How was the week?',
    });

    expect(answer.sent).toBe(true);
    expect(sentBodies).toEqual(['How was the week?']);
    expect(emitted[0].room).toBe(roomFor(COACH, CLIENT));
  });

  /// The same message is "mine" to one side and not the other, so the broadcast never claims it.
  it('should broadcast who wrote it rather than whose it is', async () => {
    const { gateway, socket, emitted } = gatewayWith();

    await gateway.send(socket('good', COACH), {
      other_user_id: CLIENT,
      body: 'Hello',
    });

    expect(emitted[0].payload.sender_user_id).toBe(COACH);
    expect(emitted[0].payload.mine).toBeUndefined();
  });

  it('should store nothing when the grant is gone', async () => {
    const { gateway, socket, sentBodies, emitted } = gatewayWith({
      allowed: false,
    });

    expect(
      await gateway.send(socket('good', COACH), {
        other_user_id: CLIENT,
        body: 'Hello',
      }),
    ).toEqual({ sent: false });
    expect(sentBodies).toEqual([]);
    expect(emitted).toEqual([]);
  });

  it('should ignore an empty body', async () => {
    const { gateway, socket, sentBodies } = gatewayWith();

    expect(
      await gateway.send(socket('good', COACH), { other_user_id: CLIENT }),
    ).toEqual({
      sent: false,
    });
    expect(sentBodies).toEqual([]);
  });
});
