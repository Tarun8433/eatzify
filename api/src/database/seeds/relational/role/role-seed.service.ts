import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RoleEntity } from '../../../../roles/infrastructure/persistence/relational/entities/role.entity';
import { RoleEnum } from '../../../../roles/roles.enum';

@Injectable()
export class RoleSeedService {
  constructor(
    @InjectRepository(RoleEntity)
    private readonly repository: Repository<RoleEntity>,
  ) {}

  /// docs/10 §1. Idempotent by id, so re-running the seed on an environment that already has the
  /// boilerplate's two roles adds the six new ones without touching a user's existing role.
  private static readonly ROLES: ReadonlyArray<{ id: RoleEnum; name: string }> =
    [
      { id: RoleEnum.user, name: 'User' },
      { id: RoleEnum.admin, name: 'Admin' },
      { id: RoleEnum.coach_l1, name: 'Affiliate Partner' },
      { id: RoleEnum.coach_l2, name: 'Verified Coach' },
      { id: RoleEnum.coach_l3, name: 'Coaching Partner' },
      { id: RoleEnum.partner_org, name: 'Partner Organisation' },
      { id: RoleEnum.support, name: 'Support' },
      { id: RoleEnum.super_admin, name: 'Super Admin' },
    ];

  async run() {
    for (const role of RoleSeedService.ROLES) {
      const existing = await this.repository.count({ where: { id: role.id } });
      if (existing) continue;

      await this.repository.save(this.repository.create(role));
    }
  }
}
