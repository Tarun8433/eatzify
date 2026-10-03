import { ConflictException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { CoachApplicationEntity } from '../coach/entities/coach-application.entity';
import { PartnerKycEntity } from '../partner/entities/payout.entity';
import { RoleEnum } from '../roles/roles.enum';
import { StatusEnum } from '../statuses/statuses.enum';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { AuditService } from './audit.service';
import type { Actor } from './admin-users.service';
import { maskEmail } from './admin-users.service';
import { STAFF_ROLES } from './permissions';

export type StaffRow = {
  user_id: number;
  name: string;
  /// Staff are listed only to a super admin, who may see contact details anyway.
  email: string | null;
  email_masked: string | null;
  role_id: number;
  role: string;
  last_login_at: string | null;
};

/// A role an admin may hand out from the Admins & Roles page: a staff role, or back to `user`.
export const ASSIGNABLE_ROLES = [...STAFF_ROLES, RoleEnum.user];

/// Admin panel plan, Phase A: who is staff, what they can do, and the verification queues' sizes.
@Injectable()
export class AdminStaffService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(CoachApplicationEntity)
    private readonly applications: Repository<CoachApplicationEntity>,
    @InjectRepository(PartnerKycEntity)
    private readonly kyc: Repository<PartnerKycEntity>,
    private readonly audit: AuditService,
  ) {}

  async staff(): Promise<StaffRow[]> {
    const rows = await this.users.find({
      where: { role: { id: In(STAFF_ROLES) } },
      relations: { role: true },
      order: { id: 'ASC' },
    });
    return rows.map((u) => ({
      user_id: u.id,
      name: [u.firstName, u.lastName].filter(Boolean).join(' '),
      email: u.email,
      email_masked: maskEmail(u.email),
      role_id: Number(u.role?.id),
      role: u.role?.name ?? '',
      last_login_at: u.lastLoginAt?.toISOString() ?? null,
    }));
  }

  /// Super admin only, behind TOTP at the controller. Nobody changes their own role — a super
  /// admin who demotes themselves by mistake would leave the panel with nobody able to undo it.
  async setRole(
    userId: number,
    roleId: RoleEnum,
    actor: Actor,
  ): Promise<StaffRow[]> {
    if (userId === actor.userId) {
      throw new ConflictException({
        status: HttpStatus.CONFLICT,
        error: {
          code: 'SELF_ACTION',
          user_message: 'You cannot change your own role.',
        },
      });
    }
    const user = await this.users.findOneOrFail({
      where: { id: userId },
      relations: { role: true },
    });
    const before = Number(user.role?.id);
    if (before !== roleId) {
      await this.users
        .createQueryBuilder()
        .update()
        .set({ role: { id: roleId } })
        .where('id = :id', { id: userId })
        .execute();
      await this.audit.record({
        actorUserId: actor.userId,
        actorRole: String(actor.roleId),
        action: 'role_change',
        resource: 'user',
        subjectUserId: userId,
        meta: { before: { role: before }, after: { role: roleId } },
        ip: actor.ip ?? null,
      });
    }
    return this.staff();
  }

  /// One screen's worth of "who is waiting on us": unconfirmed emails, coach applications and
  /// partner bank details.
  async verificationSummary(): Promise<{
    email: { pending: number; verified: number };
    coach: Record<string, number>;
    partner_kyc: Record<string, number>;
  }> {
    const [pending, verified, coach, kyc] = await Promise.all([
      this.users.count({
        where: { status: { id: StatusEnum.inactive }, isDemo: false },
      }),
      this.users.count({
        where: { status: { id: StatusEnum.active }, isDemo: false },
      }),
      this.applications
        .createQueryBuilder('a')
        .select('a.status', 'status')
        .addSelect('COUNT(*)', 'n')
        .groupBy('a.status')
        .getRawMany<{ status: string; n: string }>(),
      this.kyc
        .createQueryBuilder('k')
        .select('k.status', 'status')
        .addSelect('COUNT(*)', 'n')
        .groupBy('k.status')
        .getRawMany<{ status: string; n: string }>(),
    ]);
    const tally = (rows: { status: string; n: string }[]) =>
      Object.fromEntries(rows.map((r) => [r.status, Number(r.n)]));
    return {
      email: { pending, verified },
      coach: tally(coach),
      partner_kyc: tally(kyc),
    };
  }
}
