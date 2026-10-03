import { UserAccessService } from '../users/user-access.service';
import {
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
  UnauthorizedException,
  UnprocessableEntityException,
} from '@nestjs/common';
import ms from 'ms';
import crypto from 'crypto';
import { randomStringGenerator } from '@nestjs/common/utils/random-string-generator.util';
import { JwtService } from '@nestjs/jwt';
import bcrypt from 'bcryptjs';
import { AuthEmailLoginDto } from './dto/auth-email-login.dto';
import { AuthUpdateDto } from './dto/auth-update.dto';
import { AuthProvidersEnum } from './auth-providers.enum';
import { SocialInterface } from '../social/interfaces/social.interface';
import { AuthRegisterLoginDto } from './dto/auth-register-login.dto';
import { NullableType } from '../utils/types/nullable.type';
import { LoginResponseDto } from './dto/login-response.dto';
import { ConfigService } from '@nestjs/config';
import { JwtRefreshPayloadType } from './strategies/types/jwt-refresh-payload.type';
import { JwtPayloadType } from './strategies/types/jwt-payload.type';
import { UsersService } from '../users/users.service';
import { AllConfigType } from '../config/config.type';
import { MailService } from '../mail/mail.service';
import { RoleEnum } from '../roles/roles.enum';
import { Session } from '../session/domain/session';
import { SessionService } from '../session/session.service';
import { ProfileService } from '../profile/profile.service';
import { StatusEnum } from '../statuses/statuses.enum';
import { EmailOtpService } from './email-otp/email-otp.service';
import {
  CODE_EXPIRED,
  CODE_INVALID,
  CODE_LOCKED,
  EMAIL_NOT_VERIFIED,
  EMAIL_TAKEN,
  INVALID_CREDENTIALS,
} from './auth-copy';

/// What every way in returns (docs/09 §3).
export type AppSession = {
  access: string;
  refresh: string;
  user: User;
  onboarding_required: boolean;
};
import { User } from '../users/domain/user';

@Injectable()
export class AuthService {
  constructor(
    private readonly jwtService: JwtService,
    private readonly usersService: UsersService,
    private readonly sessionService: SessionService,
    private readonly profileService: ProfileService,
    private readonly mailService: MailService,
    private readonly configService: ConfigService<AllConfigType>,
    private readonly emailOtp: EmailOtpService,
    private readonly access: UserAccessService,
  ) {}

  /// D-250: email and password are the way in. One message for an unknown email and a wrong
  /// password, so this route cannot be used to test which addresses have accounts.
  async validateLogin(loginDto: AuthEmailLoginDto): Promise<AppSession> {
    const user = await this.usersService.findByEmail(
      loginDto.email.trim().toLowerCase(),
    );
    const passwordOk =
      !!user?.password &&
      (await bcrypt.compare(loginDto.password, user.password));
    if (!user || user.provider !== AuthProvidersEnum.email || !passwordOk) {
      throw this.refuse(
        HttpStatus.UNAUTHORIZED,
        'INVALID_CREDENTIALS',
        INVALID_CREDENTIALS,
      );
    }

    // Right password, email never confirmed: send a fresh code and send them to the code screen.
    if (user.status?.id?.toString() === StatusEnum.inactive.toString()) {
      await this.emailOtp
        .issue(Number(user.id), user.email!)
        // Over the hourly limit: the code already sent still works, and the 403 below routes there.
        .catch(() => undefined);
      throw this.refuse(
        HttpStatus.FORBIDDEN,
        'EMAIL_NOT_VERIFIED',
        EMAIL_NOT_VERIFIED,
      );
    }

    return this.issueSession(user);
  }

  private refuse(
    status: HttpStatus,
    code: string,
    userMessage: string,
  ): HttpException {
    return new HttpException(
      { status, error: { code, user_message: userMessage } },
      status,
    );
  }

  /// One session shape for every way in (docs/09 §3): the app stores `access` and `refresh` and
  /// asks the server, never itself, whether onboarding is done.
  async issueSession(user: User): Promise<AppSession> {
    // Every way in comes through here, so a blocked account is refused once, for all of them.
    const now = new Date();
    await this.access.refuseIfBlocked(Number(user.id), now);
    const hash = crypto
      .createHash('sha256')
      .update(randomStringGenerator())
      .digest('hex');

    const session = await this.sessionService.create({ user, hash });
    await this.access.recordLogin(Number(user.id), now);

    const { token, refreshToken } = await this.getTokensData({
      id: user.id,
      role: user.role,
      sessionId: session.id,
      hash,
    });

    return {
      access: token,
      refresh: refreshToken,
      user,
      onboarding_required: !(await this.profileService.hasCompletedOnboarding(
        Number(user.id),
      )),
    };
  }

  async validateSocialLogin(
    authProvider: string,
    socialData: SocialInterface,
  ): Promise<LoginResponseDto> {
    let user: NullableType<User> = null;
    const socialEmail = socialData.email?.toLowerCase();
    let userByEmail: NullableType<User> = null;

    if (socialEmail && !socialData.emailVerified) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        errors: {
          email: 'emailNotVerified',
        },
      });
    }

    if (socialEmail) {
      userByEmail = await this.usersService.findByEmail(socialEmail);
    }

    if (socialData.id) {
      user = await this.usersService.findBySocialIdAndProvider({
        socialId: socialData.id,
        provider: authProvider,
      });
    }

    if (user) {
      if (socialEmail && !userByEmail) {
        user.email = socialEmail;
      }
      await this.usersService.update(user.id, user);
    } else if (userByEmail) {
      user = userByEmail;

      if (user.status?.id?.toString() === StatusEnum.inactive.toString()) {
        user.provider = authProvider;
        user.socialId = socialData.id;

        await this.usersService.update(user.id, user);
      }
    } else if (socialData.id) {
      const role = {
        id: RoleEnum.user,
      };
      const status = {
        id: StatusEnum.active,
      };

      user = await this.usersService.create({
        email: socialEmail ?? null,
        firstName: socialData.firstName ?? null,
        lastName: socialData.lastName ?? null,
        socialId: socialData.id,
        provider: authProvider,
        role,
        status,
      });

      user = await this.usersService.findById(user.id);
    }

    if (!user) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        errors: {
          user: 'userNotFound',
        },
      });
    }

    const hash = crypto
      .createHash('sha256')
      .update(randomStringGenerator())
      .digest('hex');

    // Same gate as issueSession: Google sign-in builds its session on its own.
    const now = new Date();
    await this.access.refuseIfBlocked(Number(user.id), now);
    const session = await this.sessionService.create({
      user,
      hash,
    });
    await this.access.recordLogin(Number(user.id), now);

    const {
      token: jwtToken,
      refreshToken,
      tokenExpires,
    } = await this.getTokensData({
      id: user.id,
      role: user.role,
      sessionId: session.id,
      hash,
    });

    return {
      refreshToken,
      token: jwtToken,
      tokenExpires,
      user,
    };
  }

  /// D-250: an account starts inactive and becomes usable once the emailed code is entered.
  async register(dto: AuthRegisterLoginDto): Promise<void> {
    const email = dto.email.trim().toLowerCase();
    const existing = await this.usersService.findByEmail(email);

    if (
      existing &&
      existing.status?.id?.toString() !== StatusEnum.inactive.toString()
    ) {
      throw this.refuse(HttpStatus.CONFLICT, 'EMAIL_TAKEN', EMAIL_TAKEN);
    }

    // Signing up again before confirming replaces the password and number — whoever confirms the
    // code owns the inbox, so only they can finish it.
    const user = existing
      ? await this.usersService.update(existing.id, {
          password: dto.password,
          phone: dto.phone_e164,
        })
      : await this.usersService.create({
          email,
          password: dto.password,
          phone: dto.phone_e164,
          firstName: dto.firstName ?? null,
          lastName: dto.lastName ?? null,
          provider: AuthProvidersEnum.email,
          role: { id: RoleEnum.user },
          status: { id: StatusEnum.inactive },
        });

    await this.emailOtp.issue(Number(user!.id), email);
  }

  /// The code from the email. Right → the account opens and a session starts.
  async verifyEmail(emailRaw: string, code: string): Promise<AppSession> {
    const user = await this.usersService.findByEmail(
      emailRaw.trim().toLowerCase(),
    );
    if (!user)
      throw this.refuse(
        HttpStatus.UNPROCESSABLE_ENTITY,
        'CODE_INVALID',
        CODE_INVALID,
      );

    const result = await this.emailOtp.verify(Number(user.id), code);
    if (result === 'expired') {
      throw this.refuse(
        HttpStatus.UNPROCESSABLE_ENTITY,
        'CODE_EXPIRED',
        CODE_EXPIRED,
      );
    }
    if (result === 'locked') {
      throw this.refuse(
        HttpStatus.UNPROCESSABLE_ENTITY,
        'CODE_LOCKED',
        CODE_LOCKED,
      );
    }
    if (result !== 'ok') {
      throw this.refuse(
        HttpStatus.UNPROCESSABLE_ENTITY,
        'CODE_INVALID',
        CODE_INVALID,
      );
    }

    const active =
      (await this.usersService.update(user.id, {
        status: { id: StatusEnum.active },
      })) ?? user;
    return this.issueSession(active);
  }

  /// Always answers the same way whether or not the email exists (only the hourly limit speaks).
  async resendCode(emailRaw: string): Promise<void> {
    const user = await this.usersService.findByEmail(
      emailRaw.trim().toLowerCase(),
    );
    if (
      user?.email &&
      user.status?.id?.toString() === StatusEnum.inactive.toString()
    ) {
      await this.emailOtp.issue(Number(user.id), user.email);
    }
  }

  async confirmEmail(hash: string): Promise<void> {
    let userId: User['id'];

    try {
      const jwtData = await this.jwtService.verifyAsync<{
        confirmEmailUserId: User['id'];
      }>(hash, {
        secret: this.configService.getOrThrow('auth.confirmEmailSecret', {
          infer: true,
        }),
        algorithms: ['HS256'],
      });

      userId = jwtData.confirmEmailUserId;
    } catch {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        errors: {
          hash: `invalidHash`,
        },
      });
    }

    const user = await this.usersService.findById(userId);

    if (
      !user ||
      user?.status?.id?.toString() !== StatusEnum.inactive.toString()
    ) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: `notFound`,
      });
    }

    user.status = {
      id: StatusEnum.active,
    };

    await this.usersService.update(user.id, user);
  }

  async confirmNewEmail(hash: string): Promise<void> {
    let userId: User['id'];
    let newEmail: User['email'];

    try {
      const jwtData = await this.jwtService.verifyAsync<{
        confirmEmailUserId: User['id'];
        newEmail: User['email'];
      }>(hash, {
        secret: this.configService.getOrThrow('auth.confirmEmailSecret', {
          infer: true,
        }),
        algorithms: ['HS256'],
      });

      userId = jwtData.confirmEmailUserId;
      newEmail = jwtData.newEmail;
    } catch {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        errors: {
          hash: `invalidHash`,
        },
      });
    }

    const user = await this.usersService.findById(userId);

    if (!user) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: `notFound`,
      });
    }

    user.email = newEmail;
    user.status = {
      id: StatusEnum.active,
    };

    await this.usersService.update(user.id, user);
  }

  /// D-250: answers the same whether or not the email is registered.
  async forgotPassword(emailRaw: string): Promise<void> {
    const email = emailRaw.trim().toLowerCase();
    const user = await this.usersService.findByEmail(email);
    if (!user) return;

    const tokenExpiresIn = this.configService.getOrThrow('auth.forgotExpires', {
      infer: true,
    });

    const tokenExpires = Date.now() + ms(tokenExpiresIn);

    const hash = await this.jwtService.signAsync(
      {
        forgotUserId: user.id,
      },
      {
        secret: this.getForgotSecret(user),
        expiresIn: tokenExpiresIn,
      },
    );

    await this.mailService.forgotPassword({
      to: email,
      data: {
        hash,
        tokenExpires,
      },
    });
  }

  async resetPassword(hash: string, password: string): Promise<void> {
    let userId: User['id'] | undefined;

    try {
      const jwtData = this.jwtService.decode<{
        forgotUserId?: User['id'];
      } | null>(hash);

      userId = jwtData?.forgotUserId;
    } catch {
      userId = undefined;
    }

    let user: NullableType<User> = null;

    if (userId !== undefined && userId !== null) {
      try {
        user = await this.usersService.findById(userId);
      } catch {
        user = null;
      }
    }

    if (!user) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        errors: {
          hash: `invalidHash`,
        },
      });
    }

    try {
      await this.jwtService.verifyAsync(hash, {
        secret: this.getForgotSecret(user),
        algorithms: ['HS256'],
      });
    } catch {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        errors: {
          hash: `invalidHash`,
        },
      });
    }

    user.password = password;

    await this.sessionService.deleteByUserId({
      userId: user.id,
    });

    await this.usersService.update(user.id, user);
  }

  async me(userJwtPayload: JwtPayloadType): Promise<NullableType<User>> {
    return this.usersService.findById(userJwtPayload.id);
  }

  async update(
    userJwtPayload: JwtPayloadType,
    userDto: AuthUpdateDto,
  ): Promise<NullableType<User>> {
    const currentUser = await this.usersService.findById(userJwtPayload.id);

    if (!currentUser) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        errors: {
          user: 'userNotFound',
        },
      });
    }

    if (userDto.password) {
      if (!userDto.oldPassword) {
        throw new UnprocessableEntityException({
          status: HttpStatus.UNPROCESSABLE_ENTITY,
          errors: {
            oldPassword: 'missingOldPassword',
          },
        });
      }

      if (!currentUser.password) {
        throw new UnprocessableEntityException({
          status: HttpStatus.UNPROCESSABLE_ENTITY,
          errors: {
            oldPassword: 'incorrectOldPassword',
          },
        });
      }

      const isValidOldPassword = await bcrypt.compare(
        userDto.oldPassword,
        currentUser.password,
      );

      if (!isValidOldPassword) {
        throw new UnprocessableEntityException({
          status: HttpStatus.UNPROCESSABLE_ENTITY,
          errors: {
            oldPassword: 'incorrectOldPassword',
          },
        });
      } else {
        await this.sessionService.deleteByUserIdWithExclude({
          userId: currentUser.id,
          excludeSessionId: userJwtPayload.sessionId,
        });
      }
    }

    if (userDto.email && userDto.email !== currentUser.email) {
      const userByEmail = await this.usersService.findByEmail(userDto.email);

      if (userByEmail && userByEmail.id !== currentUser.id) {
        throw new UnprocessableEntityException({
          status: HttpStatus.UNPROCESSABLE_ENTITY,
          errors: {
            email: 'emailExists',
          },
        });
      }

      const hash = await this.jwtService.signAsync(
        {
          confirmEmailUserId: currentUser.id,
          newEmail: userDto.email,
        },
        {
          secret: this.configService.getOrThrow('auth.confirmEmailSecret', {
            infer: true,
          }),
          expiresIn: this.configService.getOrThrow('auth.confirmEmailExpires', {
            infer: true,
          }),
        },
      );

      await this.mailService.confirmNewEmail({
        to: userDto.email,
        data: {
          hash,
        },
      });
    }

    delete userDto.email;
    delete userDto.oldPassword;

    await this.usersService.update(userJwtPayload.id, userDto);

    return this.usersService.findById(userJwtPayload.id);
  }

  async refreshToken(
    data: Pick<JwtRefreshPayloadType, 'sessionId' | 'hash'>,
  ): Promise<Omit<LoginResponseDto, 'user'>> {
    const hash = crypto
      .createHash('sha256')
      .update(randomStringGenerator())
      .digest('hex');

    const session = await this.sessionService.updateByHash(
      { id: data.sessionId, hash: data.hash },
      { hash },
    );

    if (!session) {
      throw new UnauthorizedException();
    }

    const user = await this.usersService.findById(session.user.id);

    if (!user?.role) {
      throw new UnauthorizedException();
    }
    await this.access.refuseIfBlocked(Number(user.id), new Date());
    // Admin panel plan, Phase D: a refresh means the app is open today.
    await this.access.recordActive(Number(user.id), new Date());

    const { token, refreshToken, tokenExpires } = await this.getTokensData({
      id: session.user.id,
      role: {
        id: user.role.id,
      },
      sessionId: session.id,
      hash,
    });

    return {
      token,
      refreshToken,
      tokenExpires,
    };
  }

  async softDelete(userJwtPayload: JwtPayloadType): Promise<void> {
    await this.usersService.remove(userJwtPayload.id);
  }

  async logout(data: Pick<JwtPayloadType, 'sessionId'>) {
    return this.sessionService.deleteById(data.sessionId);
  }

  private invalidLoginException(
    errors: Record<string, string>,
  ): UnprocessableEntityException {
    const uniformErrors = this.configService.getOrThrow('auth.uniformErrors', {
      infer: true,
    });

    return new UnprocessableEntityException({
      status: HttpStatus.UNPROCESSABLE_ENTITY,
      errors: uniformErrors
        ? {
            email: 'incorrectEmailOrPassword',
            password: 'incorrectEmailOrPassword',
          }
        : errors,
    });
  }

  private getForgotSecret(user: User): string {
    // The secret embeds the current password hash, so every outstanding
    // reset link stops verifying as soon as the password changes — this is
    // what makes reset links single-use without storing anything extra.
    const forgotSecret = this.configService.getOrThrow('auth.forgotSecret', {
      infer: true,
    });

    return `${forgotSecret}${user.password ?? ''}`;
  }

  private async getTokensData(data: {
    id: User['id'];
    role: User['role'];
    sessionId: Session['id'];
    hash: Session['hash'];
  }) {
    const tokenExpiresIn = this.configService.getOrThrow('auth.expires', {
      infer: true,
    });

    const tokenExpires = Date.now() + ms(tokenExpiresIn);

    const [token, refreshToken] = await Promise.all([
      await this.jwtService.signAsync(
        {
          id: data.id,
          role: data.role,
          sessionId: data.sessionId,
        },
        {
          secret: this.configService.getOrThrow('auth.secret', { infer: true }),
          expiresIn: tokenExpiresIn,
        },
      ),
      await this.jwtService.signAsync(
        {
          sessionId: data.sessionId,
          hash: data.hash,
        },
        {
          secret: this.configService.getOrThrow('auth.refreshSecret', {
            infer: true,
          }),
          expiresIn: this.configService.getOrThrow('auth.refreshExpires', {
            infer: true,
          }),
        },
      ),
    ]);

    return {
      token,
      refreshToken,
      tokenExpires,
    };
  }
}
