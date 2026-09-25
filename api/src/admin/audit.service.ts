import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash } from 'node:crypto';
import { Repository } from 'typeorm';
import {
  AuditLogEntity,
  type AuditAction,
  type AuditReason,
} from './entities/audit-log.entity';

export interface AuditEntry {
  actorUserId: number | null;
  actorRole: string;
  action: AuditAction;
  resource: string;
  subjectUserId?: number | null;
  meta?: Record<string, unknown>;
  reason?: AuditReason | null;
  ip?: string | null;
}

/// Writing the log, and reading it back for `GET /admin/audit` (docs/09 §9).
///
/// One service, because "record what happened" must be the same code everywhere it is called from.
/// Two call sites that each build their own row is how an audit trail ends up with two shapes and
/// no way to query across them.
@Injectable()
export class AuditService {
  constructor(
    @InjectRepository(AuditLogEntity)
    private readonly log: Repository<AuditLogEntity>,
  ) {}

  /**
   * Append one row.
   *
   * Deliberately NOT fire-and-forget. An admin action whose audit row failed to write has not
   * happened as far as docs/09 §9 is concerned, so the caller awaits this and a failure takes the
   * request down with it — the alternative is a verification with no record that anyone made it.
   */
  async record(entry: AuditEntry): Promise<void> {
    // `save`, not `insert`: `insert` takes a QueryDeepPartialEntity, which cannot express a free
    // `Record<string, unknown>` jsonb column without casting the type away. `save` takes a
    // DeepPartial, which can. The row has no id yet, so this is an INSERT either way.
    const row = this.log.create({
      actorUserId: entry.actorUserId,
      actorRole: entry.actorRole,
      action: entry.action,
      resource: entry.resource,
      subjectUserId: entry.subjectUserId ?? null,
      meta: entry.meta ?? {},
      reason: entry.reason ?? null,
      ipHash: this.hashIp(entry.ip),
    });

    await this.log.save(row);
  }

  /// docs/09 §9: `GET /admin/audit?actor=&subject=&from=&to=`.
  async search(filter: {
    actorUserId?: number;
    subjectUserId?: number;
    from?: Date;
    to?: Date;
    limit?: number;
  }): Promise<AuditLogEntity[]> {
    const q = this.log.createQueryBuilder('a').orderBy('a.createdAt', 'DESC');

    if (filter.actorUserId !== undefined) {
      q.andWhere('a.actorUserId = :actor', { actor: filter.actorUserId });
    }
    if (filter.subjectUserId !== undefined) {
      q.andWhere('a.subjectUserId = :subject', {
        subject: filter.subjectUserId,
      });
    }
    if (filter.from) q.andWhere('a.createdAt >= :from', { from: filter.from });
    if (filter.to) q.andWhere('a.createdAt <= :to', { to: filter.to });

    // Capped rather than optional. An un-paged audit query is the one endpoint guaranteed to grow
    // without limit, and the first person to run it unfiltered would pull the whole table.
    return q.take(Math.min(filter.limit ?? 100, 500)).getMany();
  }

  /// Salted with nothing, because it does not need to be reversible — it exists to answer "was this
  /// the same origin as that?", never "which address was it?".
  private hashIp(ip: string | null | undefined): string | null {
    if (!ip) return null;
    return createHash('sha256').update(ip).digest('hex');
  }
}
