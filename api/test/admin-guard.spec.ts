import { GUARDS_METADATA } from '@nestjs/common/constants';
import { AdminController } from '../src/admin/admin.controller';
import { RolesGuard } from '../src/roles/roles.guard';
import { RoleEnum } from '../src/roles/roles.enum';

/// D-238. The guard decorators once sat on a DTO class that had been inserted between them and
/// `@Controller`, so every `/admin/*` route on this controller answered without a login. The
/// decorators compiled fine on the DTO, so only a check on the controller itself catches it.

describe('AdminController', () => {
  it('should guard the whole class with the JWT and roles guards', () => {
    const guards: unknown[] =
      Reflect.getMetadata(GUARDS_METADATA, AdminController) ?? [];

    expect(guards).toContain(RolesGuard);
    // AuthGuard('jwt') is a mixin class, so it is matched by being the other guard present.
    expect(guards).toHaveLength(2);
  });

  it('should admit only admin and super_admin', () => {
    expect(Reflect.getMetadata('roles', AdminController)).toEqual([
      RoleEnum.admin,
      RoleEnum.super_admin,
    ]);
  });
});
