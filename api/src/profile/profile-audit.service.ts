import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { EntityManager, Repository } from 'typeorm';
import { ProfileChangeEntity } from './entities/profile-change.entity';

export type FieldChange = {
  field: string;
  oldValue: string | null;
  newValue: string | null;
};

export type ChangeView = {
  field: string;
  entity: string;
  old_value: string | null;
  new_value: string | null;
  changed_at: Date;
  changed_by_user_id: number;
  source: string;
};

/// Writes and reads the append-only record of what changed on a profile (D-73).
///
/// Nothing here ever updates or deletes a row. An audit you can edit answers a different question
/// from the one it was built for.
@Injectable()
export class ProfileAuditService {
  constructor(
    @InjectRepository(ProfileChangeEntity)
    private readonly changes: Repository<ProfileChangeEntity>,
  ) {}

  /// Compares two records field by field and returns only what actually moved.
  ///
  /// A PATCH that re-sends the same value is not a change, and recording it would make "changed
  /// their name 20 times" mean "pressed Save 20 times" instead.
  static diff(
    before: Record<string, unknown>,
    after: Record<string, unknown>,
  ): FieldChange[] {
    const fields = new Set([...Object.keys(before), ...Object.keys(after)]);
    const changed: FieldChange[] = [];

    for (const field of fields) {
      const oldValue = ProfileAuditService.toText(before[field]);
      const newValue = ProfileAuditService.toText(after[field]);
      if (oldValue !== newValue) changed.push({ field, oldValue, newValue });
    }

    return changed.sort((a, b) => a.field.localeCompare(b.field));
  }

  /// Everything becomes text. An array is sorted first so `[a,b]` and `[b,a]` are not recorded as a
  /// change — a re-ordered set of allergies is the same set.
  private static toText(value: unknown): string | null {
    if (value === null || value === undefined) return null;
    if (Array.isArray(value)) return [...value].map(String).sort().join(',');
    return String(value);
  }

  /// Records a diff. Takes the transaction's manager so the audit lands or fails WITH the write it
  /// describes — an audit row for a change that rolled back is worse than none.
  async record(
    manager: EntityManager,
    input: {
      userId: number;
      entity: string;
      changes: FieldChange[];
      changedByUserId: number;
      source: string;
    },
  ): Promise<void> {
    if (input.changes.length === 0) return;

    await manager.save(
      ProfileChangeEntity,
      input.changes.map((c) => ({
        userId: input.userId,
        entity: input.entity,
        field: c.field,
        oldValue: c.oldValue,
        newValue: c.newValue,
        changedByUserId: input.changedByUserId,
        source: input.source,
      })),
    );
  }

  /// Newest first. `field` narrows to one field's history — "every name this user has had".
  async history(
    userId: number,
    options: { field?: string; limit?: number } = {},
  ): Promise<ChangeView[]> {
    const rows = await this.changes.find({
      where: { userId, ...(options.field ? { field: options.field } : {}) },
      order: { changedAt: 'DESC' },
      take: Math.min(options.limit ?? 100, 500),
    });

    return rows.map((r) => ({
      field: r.field,
      entity: r.entity,
      old_value: r.oldValue,
      new_value: r.newValue,
      changed_at: r.changedAt,
      changed_by_user_id: r.changedByUserId,
      source: r.source,
    }));
  }
}
