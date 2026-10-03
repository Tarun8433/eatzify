import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  HttpStatus,
  Injectable,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import { can, type Permission } from './permissions';

const PERMIT_KEY = 'admin-permit';

/// What a route needs. On a class it applies to every handler; a handler's own `@Permit` wins.
export const Permit = (permission: Permission) =>
  SetMetadata(PERMIT_KEY, permission);

/// Admin panel plan, Phase A: refuses an admin route unless the caller's role carries the
/// permission (`permissions.ts`). A route with no `@Permit` is refused too — a new route must say
/// who may use it rather than being open by default.
@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const needed = this.reflector.getAllAndOverride<Permission | undefined>(
      PERMIT_KEY,
      [context.getHandler(), context.getClass()],
    );
    const request = context
      .switchToHttp()
      .getRequest<RequestWithUser<JwtPayloadType | undefined>>();

    if (needed && can(request.user?.role?.id, needed)) return true;
    throw new ForbiddenException({
      status: HttpStatus.FORBIDDEN,
      error: {
        code: 'ADMIN_PERMISSION_REQUIRED',
        user_message: 'Your admin role does not include this.',
      },
    });
  }
}
