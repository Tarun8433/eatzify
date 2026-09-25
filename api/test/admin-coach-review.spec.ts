import {
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { AdminCoachService } from '../src/admin/admin-coach.service';
import type { CoachApplicationEntity } from '../src/coach/entities/coach-application.entity';
import type { AuditEntry } from '../src/admin/audit.service';
import { RoleEnum } from '../src/roles/roles.enum';

/// docs/09 §9 + docs/12 §6. The half of partner onboarding the coach surface deliberately cannot
/// reach: level 2 is "ID + qualification document on file", where on file means a human looked and
/// said so. Before this service the columns to record that decision existed and nothing wrote them.

function serviceWith(
  existing: Partial<CoachApplicationEntity> | null,
  userRole: RoleEnum = RoleEnum.coach_l1,
) {
  let row = existing as CoachApplicationEntity | null;
  const audits: AuditEntry[] = [];
  const roleUpdates: { userId: number; roleId: number }[] = [];
  const user = { id: 7, role: { id: userRole } };

  const service = new AdminCoachService(
    {
      findOne: () => Promise.resolve(row),
      find: () => Promise.resolve(row ? [row] : []),
      save: (next: CoachApplicationEntity) => {
        row = { ...row, ...next } as CoachApplicationEntity;
        return Promise.resolve(row);
      },
    } as never,
    {
      findOne: () => Promise.resolve(user),
      find: () => Promise.resolve([user]),
      update: (userId: number, patch: { role: { id: number } }) => {
        roleUpdates.push({ userId, roleId: patch.role.id });
        user.role = { id: patch.role.id };
        return Promise.resolve({});
      },
    } as never,
    // Profiles: a phone-OTP signup has no name on the user row, so the service falls back here.
    {
      findOne: () => Promise.resolve({ userId: 7, name: 'Profile Name' }),
      find: () => Promise.resolve([{ userId: 7, name: 'Profile Name' }]),
    } as never,
    // Files: the local driver stores a URL path; only the basename is ever used.
    {
      findById: (id: string) =>
        Promise.resolve({ id, path: `/api/v1/files/${id}.jpg` }),
    } as never,
    {
      record: (entry: AuditEntry) => {
        audits.push(entry);
        return Promise.resolve();
      },
    } as never,
  );

  return { service, audits, roleUpdates, current: () => row };
}

async function refusal(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (
      e as UnprocessableEntityException | NotFoundException
    ).getResponse() as { error: { code: string } };
    return body.error.code;
  }
  throw new Error('expected the request to be refused');
}

const SUBMITTED: Partial<CoachApplicationEntity> = {
  id: 'app-1',
  userId: 7,
  status: 'submitted',
  discipline: 'nutritionist',
  agreementAcceptedAt: new Date('2026-09-01T00:00:00Z'),
  agreementVersion: 'v1',
  idDocumentFileId: '11111111-1111-1111-1111-111111111111',
  qualificationDocumentFileId: '22222222-2222-2222-2222-222222222222',
  submittedAt: new Date('2026-09-02T00:00:00Z'),
  verifiedAttributes: [],
  rejectionReason: null,
  reviewedAt: null,
  reviewedByUserId: null,
};

const REVIEWER = { userId: 99, role: 'admin', ip: '203.0.113.7' };

describe('verifying a partner application', () => {
  it('should record what was checked rather than that the person is qualified', async () => {
    const { service, current } = serviceWith({ ...SUBMITTED });

    await service.verify(7, ['government_id', 'dietetics_degree'], REVIEWER);

    expect(current()?.status).toBe('verified');
    // doc 00 §8: Eatzify is not an accrediting body. The stored claim is the documents it saw.
    expect(current()?.verifiedAttributes).toEqual([
      'government_id',
      'dietetics_degree',
    ]);
  });

  it('should refuse a verification when nothing is recorded as checked', async () => {
    const { service, current } = serviceWith({ ...SUBMITTED });

    expect(await refusal(service.verify(7, [], REVIEWER))).toBe(
      'VERIFIED_ATTRIBUTES_REQUIRED',
    );
    // Still awaiting review, not silently half-decided.
    expect(current()?.status).toBe('submitted');
  });

  it('should name the admin who decided when an application is verified', async () => {
    const { service, current } = serviceWith({ ...SUBMITTED });

    await service.verify(7, ['government_id'], REVIEWER);

    expect(current()?.reviewedByUserId).toBe(99);
    expect(current()?.reviewedAt).toBeInstanceOf(Date);
  });

  it('should raise the applicant to coach_l2 when verified (docs/10 §1)', async () => {
    const { service, roleUpdates } = serviceWith({ ...SUBMITTED });

    await service.verify(7, ['government_id'], REVIEWER);

    expect(roleUpdates).toEqual([{ userId: 7, roleId: RoleEnum.coach_l2 }]);
  });

  it('should not demote an active coach when a verification lands late', async () => {
    const { service, roleUpdates } = serviceWith(
      { ...SUBMITTED },
      RoleEnum.coach_l3,
    );

    await service.verify(7, ['government_id'], REVIEWER);

    // A verification landing after the coaching relationship started must not undo it.
    expect(roleUpdates).toEqual([]);
  });

  it('should write an audit row carrying claimed against confirmed', async () => {
    const { service, audits } = serviceWith({ ...SUBMITTED });

    await service.verify(7, ['government_id'], REVIEWER);

    expect(audits).toHaveLength(1);
    expect(audits[0].action).toBe('coach_verify');
    expect(audits[0].actorUserId).toBe(99);
    expect(audits[0].subjectUserId).toBe(7);
    // The gap between what was said and what was seen is the fraud signal worth keeping.
    expect(audits[0].meta).toEqual({
      verified_attributes: ['government_id'],
      declared_discipline: 'nutritionist',
    });
  });

  it('should clear a previous rejection reason when the application is approved', async () => {
    const { service, current } = serviceWith({
      ...SUBMITTED,
      rejectionReason: 'Document unreadable',
    });

    await service.verify(7, ['government_id'], REVIEWER);

    expect(current()?.rejectionReason).toBeNull();
  });
});

describe('rejecting a partner application', () => {
  it('should refuse a rejection when no reason is given', async () => {
    const { service, current } = serviceWith({ ...SUBMITTED });

    expect(await refusal(service.reject(7, '   ', REVIEWER))).toBe(
      'REJECTION_REASON_REQUIRED',
    );
    expect(current()?.status).toBe('submitted');
  });

  it('should store the reason and who decided when rejecting', async () => {
    const { service, current, audits } = serviceWith({ ...SUBMITTED });

    await service.reject(
      7,
      '  Qualification document was unreadable.  ',
      REVIEWER,
    );

    expect(current()?.status).toBe('rejected');
    expect(current()?.rejectionReason).toBe(
      'Qualification document was unreadable.',
    );
    expect(current()?.reviewedByUserId).toBe(99);
    expect(audits[0].action).toBe('coach_reject');
  });

  it('should not demote when an application is rejected (docs/12 §6)', async () => {
    const { service, roleUpdates } = serviceWith({ ...SUBMITTED });

    await service.reject(7, 'Not enough evidence.', REVIEWER);

    expect(roleUpdates).toEqual([]);
  });
});

describe('what may be reviewed at all', () => {
  it('should refuse review when the application was never submitted', async () => {
    const { service } = serviceWith({ ...SUBMITTED, status: 'draft' });

    expect(await refusal(service.verify(7, ['government_id'], REVIEWER))).toBe(
      'APPLICATION_NOT_SUBMITTED',
    );
  });

  it('should refuse a second decision when the application is settled', async () => {
    const { service } = serviceWith({ ...SUBMITTED, status: 'verified' });

    expect(await refusal(service.reject(7, 'Changed my mind', REVIEWER))).toBe(
      'APPLICATION_NOT_SUBMITTED',
    );
  });

  it('should return not found when there is no application', async () => {
    const { service } = serviceWith(null);

    expect(await refusal(service.verify(7, ['government_id'], REVIEWER))).toBe(
      'APPLICATION_NOT_FOUND',
    );
  });
});

describe('who the applicant is', () => {
  it('should use the profile name when the user row has none (phone signup)', async () => {
    // Eatzify's primary auth in India is phone OTP (doc 20 §2), and that path never fills
    // `user.firstName` — the name is asked for at onboarding and lands on `profile.name`.
    // Reading only the user row showed "No name on file" for the majority signup path.
    const { service } = serviceWith({ ...SUBMITTED });

    const identity = await service.identity(7, REVIEWER);

    expect(identity.name).toBe('Profile Name');
  });

  it('should write a read_pii audit row naming the reader and the subject', async () => {
    const { service, audits } = serviceWith({ ...SUBMITTED });

    await service.identity(7, REVIEWER);

    expect(audits).toHaveLength(1);
    expect(audits[0].action).toBe('read_pii');
    expect(audits[0].actorUserId).toBe(99);
    expect(audits[0].subjectUserId).toBe(7);
    // rule 5 keeps PII out of logs: record WHICH fields were read, never their values.
    expect(JSON.stringify(audits[0].meta)).not.toContain('Profile Name');
  });

  it('should carry the name into the queue so the list is scannable', async () => {
    const { service } = serviceWith({ ...SUBMITTED });

    const [row] = await service.queue();

    expect(row.name).toBe('Profile Name');
  });
});

describe('the review queue', () => {
  it('should mask the applicant in the queue (docs/13 §4)', async () => {
    const { service } = serviceWith({ ...SUBMITTED });

    const [row] = await service.queue();

    expect(row.user_id).toBe(7);
    expect(row.discipline).toBe('nutritionist');
    // Booleans, not file ids: documents live behind short-lived signed URLs, not in a list.
    expect(row.has_id_document).toBe(true);
    expect(row.has_qualification_document).toBe(true);
    expect(Object.keys(row)).not.toContain('idDocumentFileId');
  });

  it('should report how long the applicant has been waiting', async () => {
    const twoDaysAgo = new Date(Date.now() - 2 * 86_400_000);
    const { service } = serviceWith({ ...SUBMITTED, submittedAt: twoDaysAgo });

    const [row] = await service.queue();

    expect(row.waiting_days).toBe(2);
  });
});
