import { AuthService } from '../src/auth/auth.service';
import { AuthProvidersEnum } from '../src/auth/auth-providers.enum';
import { StatusEnum } from '../src/statuses/statuses.enum';
import type { SocialInterface } from '../src/social/interfaces/social.interface';

type U = {
  id: number;
  email: string;
  password?: string | null;
  provider: string;
  socialId?: string;
  status: { id: number };
};

/// `POST /auth/google` through AuthService, with Google's verifier faked: the token string is the
/// lookup key into `identities`, and anything not in it fails verification.
function harness(identities: Record<string, SocialInterface>) {
  const users: U[] = [];
  const usersService = {
    findById: (id: number) =>
      Promise.resolve(users.find((u) => u.id === id) ?? null),
    findByEmail: (e: string) =>
      Promise.resolve(users.find((u) => u.email === e) ?? null),
    findBySocialIdAndProvider: (q: { socialId: string; provider: string }) =>
      Promise.resolve(
        users.find(
          (u) => u.socialId === q.socialId && u.provider === q.provider,
        ) ?? null,
      ),
    create: (d: Omit<U, 'id'>) => {
      const u = { ...d, id: users.length + 1 } as U;
      users.push(u);
      return Promise.resolve(u);
    },
    update: (id: number, patch: Partial<U>) =>
      Promise.resolve(
        Object.assign(
          users.find((x) => x.id === id)!,
          patch,
        ),
      ),
  };
  const service = new AuthService(
    { signAsync: () => Promise.resolve('jwt') } as never,
    usersService as never,
    { create: () => Promise.resolve({ id: 1 }) } as never,
    { hasCompletedOnboarding: () => Promise.resolve(false) } as never,
    {} as never,
    {
      getOrThrow: (k: string) => (k.endsWith('xpires') ? '1h' : 'secret'),
    } as never,
    {} as never,
    {
      refuseIfBlocked: () => Promise.resolve(),
      recordLogin: () => Promise.resolve(),
    } as never,
    { verify: (t: string) => Promise.resolve(identities[t] ?? null) } as never,
  );
  return { service, users };
}

const asha: SocialInterface = {
  id: 'g-1',
  email: 'Asha@Example.com',
  emailVerified: true,
  firstName: 'Asha',
};

describe('Google sign-in', () => {
  it('should create an active google account when the identity is new', async () => {
    const { service, users } = harness({ ok: asha });

    await expect(service.googleLogin('ok')).resolves.toMatchObject({
      access: 'jwt',
      onboarding_required: true,
    });
    expect(users).toEqual([
      expect.objectContaining({
        email: 'asha@example.com',
        provider: AuthProvidersEnum.google,
        socialId: 'g-1',
        status: { id: StatusEnum.active },
      }),
    ]);
  });

  it('should reuse the same account when signing in again', async () => {
    const { service, users } = harness({ ok: asha });
    await service.googleLogin('ok');
    await service.googleLogin('ok');
    expect(users).toHaveLength(1);
  });

  it('should sign in the existing confirmed email account when the address matches', async () => {
    const { service, users } = harness({ ok: asha });
    users.push({
      id: 1,
      email: 'asha@example.com',
      provider: AuthProvidersEnum.email,
      status: { id: StatusEnum.active },
    });

    await service.googleLogin('ok');
    expect(users).toHaveLength(1);
    // Still an email account: the password keeps working.
    expect(users[0].provider).toBe(AuthProvidersEnum.email);
  });

  it('should take over an unconfirmed email account when Google verifies the inbox', async () => {
    const { service, users } = harness({ ok: asha });
    users.push({
      id: 1,
      email: 'asha@example.com',
      provider: AuthProvidersEnum.email,
      status: { id: StatusEnum.inactive },
    });

    await service.googleLogin('ok');
    expect(users[0]).toMatchObject({
      provider: AuthProvidersEnum.google,
      socialId: 'g-1',
      status: { id: StatusEnum.active },
    });
  });

  it('should refuse when the token does not verify or the email is unverified', async () => {
    const { service, users } = harness({
      unverified: { ...asha, emailVerified: false },
    });
    for (const token of ['forged', 'unverified']) {
      await expect(service.googleLogin(token)).rejects.toMatchObject({
        status: 401,
        response: { error: { code: 'GOOGLE_SIGN_IN_FAILED' } },
      });
    }
    expect(users).toHaveLength(0);
  });
});

/// A Google account can add a password, so the same person can also sign in with email.
describe('password for a Google account', () => {
  it('should ask a new Google account to create a password', async () => {
    const { service } = harness({ ok: asha });

    await expect(service.googleLogin('ok')).resolves.toMatchObject({
      needs_password: true,
    });
  });

  it('should make the account an email account when the password is set', async () => {
    const { service, users } = harness({ ok: asha });
    await service.googleLogin('ok');

    await service.setPassword(1, 'longenough');

    expect(users[0]).toMatchObject({
      password: 'longenough',
      provider: AuthProvidersEnum.email,
    });
  });

  it('should still sign in with Google afterwards, without asking again', async () => {
    const { service, users } = harness({ ok: asha });
    await service.googleLogin('ok');
    await service.setPassword(1, 'longenough');

    await expect(service.googleLogin('ok')).resolves.toMatchObject({
      needs_password: false,
    });
    expect(users).toHaveLength(1);
  });

  it('should refuse when the account already has a password', async () => {
    const { service, users } = harness({ ok: asha });
    users.push({
      id: 1,
      email: 'ravi@example.com',
      password: 'hash',
      provider: AuthProvidersEnum.email,
      status: { id: StatusEnum.active },
    });

    await expect(service.setPassword(1, 'longenough')).rejects.toMatchObject({
      status: 409,
    });
  });
});
