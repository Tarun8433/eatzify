import { ForbiddenException, HttpStatus, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, Repository } from 'typeorm';
import { StatusEnum } from '../statuses/statuses.enum';
import { UserBlockEntity } from './infrastructure/persistence/relational/entities/user-block.entity';
import { UserEntity } from './infrastructure/persistence/relational/entities/user.entity';

export const ACCOUNT_BLOCKED =
  'This account has been blocked. Contact support if you think this is a mistake.';

/// Admin panel plan, Phase A: whether someone may get a session, and when they last did.
///
/// Checked at sign-in and at every token refresh. An access token already issued lives out its
/// 15 minutes; blocking deletes the person's sessions, so the next refresh is refused.
@Injectable()
export class UserAccessService {
  constructor(
    @InjectRepository(UserBlockEntity)
    private readonly blocks: Repository<UserBlockEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
  ) {}

  /// The block in force, or null. A block whose time is up is lifted here, on first contact,
  /// so an expired block never needs a job to have run.
  async openBlock(userId: number, now: Date): Promise<UserBlockEntity | null> {
    const block = await this.blocks.findOne({
      where: { userId, liftedAt: IsNull() },
    });
    if (!block) return null;
    if (block.until && block.until.getTime() <= now.getTime()) {
      await this.lift(block, null, now);
      return null;
    }
    return block;
  }

  async refuseIfBlocked(userId: number, now: Date): Promise<void> {
    if (!(await this.openBlock(userId, now))) return;
    throw new ForbiddenException({
      status: HttpStatus.FORBIDDEN,
      error: { code: 'ACCOUNT_BLOCKED', user_message: ACCOUNT_BLOCKED },
    });
  }

  async recordLogin(userId: number, now: Date): Promise<void> {
    await this.users.update({ id: userId }, { lastLoginAt: now });
  }

  async lift(
    block: UserBlockEntity,
    by: number | null,
    now: Date,
  ): Promise<void> {
    await this.blocks.update({ id: block.id }, { liftedAt: now, liftedBy: by });
    // Only a row still marked blocked goes back to active; a deleted or never-verified account
    // keeps whatever status it has.
    await this.users
      .createQueryBuilder()
      .update()
      .set({ status: { id: StatusEnum.active } })
      .where('id = :id AND "statusId" = :blocked', {
        id: block.userId,
        blocked: StatusEnum.blocked,
      })
      .execute();
  }
}
