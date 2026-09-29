import bcrypt from 'bcryptjs';
import { AuthService } from '../src/auth/auth.service';
import { StatusEnum } from '../src/statuses/statuses.enum';

type U = {
  id: number;
  email: string;
  password?: string;
  phone?: string | null;
  provider: string;
  status: { id: number };
};

/// D-250 end to end through AuthService: sign up → emailed code → verify → session, and the ways
/// in that must not reveal which emails have accounts.
function harness() {
  const users: U[] = [];
  const codes: Record<number, string> = {};
  const resetMails: string[] = [];
  const hashed = (p?: string) => (p ? bcrypt.hashSync(p, 4) : undefined);
  const usersService = {
    findByEmail: (e: string) =>
      Promise.resolve(users.find((u) => u.email === e) ?? null),
    create: (d: Omit<U, 'id'>) => {
      const u = {
        ...d,
        id: users.length + 1,
        password: hashed(d.password),
      } as U;
      users.push(u);
      return Promise.resolve(u);
    },
    update: (id: number, patch: Partial<U>) => {
      const u = users.find((x) => x.id === id)!;
      Object.assign(
        u,
        patch,
        patch.password ? { password: hashed(patch.password) } : {},
      );
      return Promise.resolve(u);
    },
  };
  const emailOtp = {
    issue: (id: number) => {
      codes[id] = '123456';
      return Promise.resolve();
    },
    verify: (id: number, code: string) =>
      Promise.resolve(codes[id] === code ? 'ok' : 'wrong'),
  };
  const config = {
    getOrThrow: (k: string) => (k.endsWith('xpires') ? '1h' : 'secret'),
  };
  const service = new AuthService(
    { signAsync: () => Promise.resolve('jwt') } as never,
    usersService as never,
    { create: () => Promise.resolve({ id: 1 }) } as never,
    { hasCompletedOnboarding: () => Promise.resolve(false) } as never,
    {
      forgotPassword: ({ to }: { to: string }) => (
        resetMails.push(to),
        Promise.resolve()
      ),
    } as never,
    config as never,
    emailOtp as never,
  );
  return { service, users, codes, resetMails };
}

const signUp = {
  email: ' Asha@Example.com ',
  password: 'longenough',
  phone_e164: '+919812345678',
};

describe('email sign-in (D-250)', () => {
  it('should sign up inactive, emails a code, and the code opens a session', async () => {
    const { service, users } = harness();
    await service.register(signUp as never);

    expect(users[0]).toMatchObject({
      email: 'asha@example.com',
      phone: '+919812345678',
      status: { id: StatusEnum.inactive },
    });
    const session = await service.verifyEmail('asha@example.com', '123456');
    expect(session).toMatchObject({
      access: 'jwt',
      refresh: 'jwt',
      onboarding_required: true,
    });
    expect(users[0].status.id).toBe(StatusEnum.active);
  });

  it('should refuse a wrong code', async () => {
    const { service } = harness();
    await service.register(signUp as never);
    await expect(
      service.verifyEmail('asha@example.com', '000000'),
    ).rejects.toMatchObject({
      response: { error: { code: 'CODE_INVALID' } },
    });
  });

  it('should refuse a second sign-up for a confirmed email', async () => {
    const { service } = harness();
    await service.register(signUp as never);
    await service.verifyEmail('asha@example.com', '123456');
    await expect(service.register(signUp as never)).rejects.toMatchObject({
      status: 409,
    });
  });

  it('should give one answer for an unknown email and a wrong password', async () => {
    const { service } = harness();
    await service.register(signUp as never);
    await service.verifyEmail('asha@example.com', '123456');

    const unknown = service.validateLogin({
      email: 'nobody@example.com',
      password: 'longenough',
    });
    const wrong = service.validateLogin({
      email: 'asha@example.com',
      password: 'wrongpassword',
    });
    for (const attempt of [unknown, wrong]) {
      await expect(attempt).rejects.toMatchObject({
        status: 401,
        response: { error: { code: 'INVALID_CREDENTIALS' } },
      });
    }
    await expect(
      service.validateLogin({
        email: 'ASHA@example.com',
        password: 'longenough',
      }),
    ).resolves.toMatchObject({ access: 'jwt' });
  });

  it('should send an unverified account back to the code screen with a fresh code', async () => {
    const { service, codes } = harness();
    await service.register(signUp as never);
    delete codes[1];

    await expect(
      service.validateLogin({
        email: 'asha@example.com',
        password: 'longenough',
      }),
    ).rejects.toMatchObject({
      status: 403,
      response: { error: { code: 'EMAIL_NOT_VERIFIED' } },
    });
    expect(codes[1]).toBe('123456');
  });

  it('should keep forgot password silent for unknown emails and mails known ones', async () => {
    const { service, resetMails } = harness();
    await service.register(signUp as never);

    await expect(
      service.forgotPassword('nobody@example.com'),
    ).resolves.toBeUndefined();
    await service.forgotPassword(' ASHA@example.com');
    expect(resetMails).toEqual(['asha@example.com']);
  });
});
