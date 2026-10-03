import { GUARDS_METADATA } from '@nestjs/common/constants';
import { AdminController } from '../src/admin/admin.controller';
import { AdminPayoutsController } from '../src/admin/admin-payouts.controller';
import { AdminUsersController } from '../src/admin/admin-users.controller';
import { AdminPaymentsController } from '../src/admin/admin-payments.controller';
import { PermissionsGuard } from '../src/admin/permissions.guard';

/// D-238. The guard decorators once sat on a DTO class that had been inserted between them and
/// `@Controller`, so every `/admin/*` route on this controller answered without a login. The
/// decorators compiled fine on the DTO, so only a check on the controller itself catches it.
///
/// Admin panel plan, Phase A: role checks became permission checks (`permissions.ts`); the class
/// still carries the JWT guard and a default permission every handler falls back to.
describe.each([
  ['AdminController', AdminController, 'users.read'],
  ['AdminUsersController', AdminUsersController, 'users.read'],
  ['AdminPayoutsController', AdminPayoutsController, 'payouts.manage'],
  ['AdminPaymentsController', AdminPaymentsController, 'payments.read'],
])('%s', (_name, controller, permission) => {
  it('should guard the whole class with the JWT and permissions guards', () => {
    const guards: unknown[] =
      Reflect.getMetadata(GUARDS_METADATA, controller) ?? [];

    expect(guards).toContain(PermissionsGuard);
    // AuthGuard('jwt') is a mixin class, so it is matched by being the other guard present.
    expect(guards).toHaveLength(2);
  });

  it('should default every route to a named permission', () => {
    expect(Reflect.getMetadata('admin-permit', controller)).toBe(permission);
  });
});
