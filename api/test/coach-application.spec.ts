import { UnprocessableEntityException } from '@nestjs/common';
import { CoachApplicationService } from '../src/coach/coach-application.service';
import type { CoachApplicationEntity } from '../src/coach/entities/coach-application.entity';
import { RoleEnum } from '../src/roles/roles.enum';
import { WHAT_VERIFICATION_MEANS } from '../src/coach/coach-copy';

/// docs/12 §6. Level 1 is "signup + agreement" and level 2 is "ID + qualification document on
/// file" — where "on file" means a human looked. The line between them is the whole point, and
/// this service is only allowed to reach the first one.

function serviceWith(
  existing: Partial<CoachApplicationEntity> | null = null,
  { role = RoleEnum.user, activeGrant = false } = {},
) {
  let row = existing as CoachApplicationEntity | null;
  const roleUpdates: { userId: number; roleId: number }[] = [];
  const user = { id: 1, role: { id: role } };

  const service = new CoachApplicationService(
    {
      findOne: () => Promise.resolve(row),
      save: (next: CoachApplicationEntity) => {
        row = { ...row, ...next } as CoachApplicationEntity;
        return Promise.resolve(row);
      },
    } as never,
    {
      findOne: () => Promise.resolve(user),
      update: (userId: number, patch: { role: { id: number } }) => {
        roleUpdates.push({ userId, roleId: patch.role.id });
        user.role = { id: patch.role.id };
        return Promise.resolve({});
      },
    } as never,
    // Grants: level 3's third condition. One active grant, or none.
    {
      findOne: () =>
        Promise.resolve(activeGrant ? { id: 'g1', status: 'active' } : null),
    } as never,
  );

  return { service, roleUpdates, current: () => row, user };
}

async function refusal(run: Promise<unknown>): Promise<string> {
  try {
    await run;
  } catch (e) {
    const body = (e as UnprocessableEntityException).getResponse() as {
      error: { code: string };
    };
    return body.error.code;
  }
  throw new Error('expected the request to be refused');
}

const ACCEPTED = {
  userId: 1,
  status: 'draft' as const,
  agreementAcceptedAt: new Date('2026-09-01T00:00:00Z'),
  agreementVersion: 'v1',
  idDocumentFileId: null,
  qualificationDocumentFileId: null,
  verifiedAttributes: [],
  rejectionReason: null,
  submittedAt: null,
};

describe('coach onboarding — the agreement (docs/12 §6 level 1)', () => {
  it('should grant the affiliate role when the agreement is accepted', async () => {
    const { service, roleUpdates } = serviceWith();

    await service.acceptAgreement(1, 'v1');

    expect(roleUpdates).toEqual([{ userId: 1, roleId: RoleEnum.coach_l1 }]);
  });

  /// Level 1 is the agreement and nothing else, so the applicant is a partner the moment it is on
  /// record — there is no queue to wait in.
  it('should record the agreement version when the agreement is accepted', async () => {
    const { service } = serviceWith();

    const view = await service.acceptAgreement(1, 'v2');

    expect(view.agreement_accepted).toBe(true);
    expect(view.agreement_version).toBe('v2');
    expect(view.level).toBe(1);
  });

  /// A partner tapping again on a slow connection must not fall back down a level, and a second
  /// acceptance must not reopen an application a reviewer already has.
  it('should change nothing when the agreement is accepted twice', async () => {
    const { service, roleUpdates } = serviceWith({
      ...ACCEPTED,
      status: 'submitted',
      submittedAt: new Date(),
    } as unknown as CoachApplicationEntity);

    const view = await service.acceptAgreement(1, 'v1');

    expect(view.status).toBe('submitted');
    expect(roleUpdates).toEqual([]);
  });
});

describe('coach onboarding — documents and review (level 2)', () => {
  it('should refuse documents when the agreement has not been accepted', async () => {
    const { service } = serviceWith();

    const code = await refusal(
      service.attachDocuments(1, { idDocumentFileId: 'f1' }),
    );

    expect(code).toBe('AGREEMENT_REQUIRED');
  });

  /// docs/12 §6 level 2 is exactly "ID + qualification document on file". Submitting with one of
  /// them asks a reviewer to verify something that is not there.
  it('should refuse submission when only one document is attached', async () => {
    const { service } = serviceWith({
      ...ACCEPTED,
      idDocumentFileId: 'f1',
    } as unknown as CoachApplicationEntity);

    const code = await refusal(service.submit(1));

    expect(code).toBe('DOCUMENTS_REQUIRED');
  });

  it('should move to review when both documents are attached', async () => {
    const { service } = serviceWith({
      ...ACCEPTED,
      idDocumentFileId: 'f1',
      qualificationDocumentFileId: 'f2',
    } as unknown as CoachApplicationEntity);

    const view = await service.submit(1);

    expect(view.status).toBe('submitted');
    expect(view.submitted_at).not.toBeNull();
  });

  /// The service can reach `submitted` and no further. Verification is
  /// `POST /admin/coaches/{id}/verify` (docs/09 §9), which is E8 and does not exist yet — so
  /// submitting must not quietly make somebody a verified partner.
  it('should stay at level 1 after submission, because only a human verifies', async () => {
    const { service, roleUpdates } = serviceWith({
      ...ACCEPTED,
      idDocumentFileId: 'f1',
      qualificationDocumentFileId: 'f2',
    } as unknown as CoachApplicationEntity);

    const view = await service.submit(1);

    expect(view.level).toBe(1);
    expect(roleUpdates).toEqual([]);
  });

  /// Otherwise a reviewer can approve one set of documents while another is being swapped in.
  it('should refuse edits while the application is in review', async () => {
    const { service } = serviceWith({
      ...ACCEPTED,
      status: 'submitted',
      idDocumentFileId: 'f1',
      qualificationDocumentFileId: 'f2',
      submittedAt: new Date(),
    } as unknown as CoachApplicationEntity);

    const code = await refusal(
      service.attachDocuments(1, { idDocumentFileId: 'f3' }),
    );

    expect(code).toBe('APPLICATION_IN_REVIEW');
  });
});

describe('coach onboarding — what the applicant is told', () => {
  /// docs/12 §6: "Publish exactly what verification means." Eatzify is not an accrediting body
  /// (doc 00 §8), so the claim it may make is "we saw this document", never "this person is
  /// qualified". Shipping it with the application means no client has to author it.
  it('should carry the verification disclaimer on every response', async () => {
    const { service } = serviceWith();

    const view = await service.acceptAgreement(1, 'v1');

    expect(view.what_verification_means).toBe(WHAT_VERIFICATION_MEANS);
    expect(view.what_verification_means).toContain(
      'does not certify or accredit',
    );
  });

  /// A file id in a response is a file id in a log. Whether a document exists is the applicant's
  /// business; the document itself is the reviewer's.
  it('should report documents as booleans rather than file ids', async () => {
    const { service } = serviceWith({
      ...ACCEPTED,
      idDocumentFileId: 'secret-file-id',
    } as unknown as CoachApplicationEntity);

    const view = await service.current(1);

    expect(view?.has_id_document).toBe(true);
    expect(JSON.stringify(view)).not.toContain('secret-file-id');
  });
});

/// D-191. What someone SAYS they do is asked once at onboarding purely to decide whether to offer
/// the partner route, and never stored — so the application is the only place the answer lives,
/// the only place it can be read back, and the only place it can be changed.
describe('what the applicant says they do', () => {
  it('should record the discipline before any agreement exists', async () => {
    const { service, current } = serviceWith();

    const view = await service.setDiscipline(1, 'nutritionist');

    expect(current()?.discipline).toBe('nutritionist');
    expect(view.discipline).toBe('nutritionist');
    // Saying what you do is not agreeing to anything.
    expect(view.agreement_accepted).toBe(false);
  });

  it('should let a draft applicant change their mind', async () => {
    const { service } = serviceWith({ ...ACCEPTED, discipline: 'trainer' });

    const view = await service.setDiscipline(1, 'doctor');

    expect(view.discipline).toBe('doctor');
  });

  /// A qualification certificate means something different for a doctor than for a trainer, so
  /// switching underneath a reviewer would invalidate the review without the reviewer knowing.
  it('should refuse a change while a human is reviewing the application', async () => {
    const { service, current } = serviceWith({
      ...ACCEPTED,
      status: 'submitted',
      discipline: 'trainer',
    });

    const code = await refusal(service.setDiscipline(1, 'doctor'));

    expect(code).toBe('APPLICATION_IN_REVIEW');
    expect(current()?.discipline).toBe('trainer');
  });

  /// Null is a real answer here: every row written before the column existed has none, and the
  /// screen asks rather than inventing one.
  it('should report no discipline when the applicant has not said', async () => {
    const { service } = serviceWith(ACCEPTED);

    expect((await service.current(1))?.discipline).toBeNull();
  });
});

/// docs/12 §6: level 3 is "level 2 + active coaching agreement + client grant" (D-235). The
/// partner supplies two of those; only a client can supply the third.
describe('level 3, Coaching Partner', () => {
  const VERIFIED = {
    ...ACCEPTED,
    status: 'verified' as const,
    coachingAgreementAcceptedAt: null,
    coachingAgreementVersion: null,
  };
  const NOW = new Date('2026-09-18T10:00:00Z');

  it('should refuse the coaching agreement before verification', async () => {
    const { service } = serviceWith(
      { ...ACCEPTED },
      { role: RoleEnum.coach_l1 },
    );

    expect(await refusal(service.acceptCoachingAgreement(1, 'c1', NOW))).toBe(
      'VERIFICATION_REQUIRED',
    );
  });

  it('should record the coaching agreement and the version shown', async () => {
    const { service, current } = serviceWith(
      { ...VERIFIED },
      { role: RoleEnum.coach_l2 },
    );

    const view = await service.acceptCoachingAgreement(1, 'c1', NOW);

    expect(current()).toMatchObject({
      coachingAgreementAcceptedAt: NOW,
      coachingAgreementVersion: 'c1',
    });
    expect(view.coaching_agreement_accepted).toBe(true);
  });

  /// Two out of three is still level 2. The client's yes is not the partner's to give.
  it('should not promote on the agreement alone, with no client', async () => {
    const { service, roleUpdates } = serviceWith(
      { ...VERIFIED },
      { role: RoleEnum.coach_l2, activeGrant: false },
    );

    const view = await service.acceptCoachingAgreement(1, 'c1', NOW);

    expect(roleUpdates).toEqual([]);
    expect(view.level).toBe(2);
  });

  it('should promote when the agreement lands after a client already said yes', async () => {
    const { service, roleUpdates } = serviceWith(
      { ...VERIFIED },
      { role: RoleEnum.coach_l2, activeGrant: true },
    );

    const view = await service.acceptCoachingAgreement(1, 'c1', NOW);

    expect(roleUpdates).toEqual([{ userId: 1, roleId: RoleEnum.coach_l3 }]);
    expect(view.level).toBe(3);
  });

  it('should promote when a client says yes after the agreement', async () => {
    const { service, roleUpdates } = serviceWith(
      {
        ...VERIFIED,
        coachingAgreementAcceptedAt: NOW,
        coachingAgreementVersion: 'c1',
      },
      { role: RoleEnum.coach_l2, activeGrant: true },
    );

    expect(await service.promoteToCoachingIfEligible(1, NOW)).toBe(true);
    expect(roleUpdates).toEqual([{ userId: 1, roleId: RoleEnum.coach_l3 }]);
  });

  /// An affiliate who somehow has a grant and an agreement is still not verified — level 3 is
  /// level 2 PLUS the rest, never instead of it.
  it('should never promote a partner who is not level 2', async () => {
    const { service, roleUpdates } = serviceWith(
      { ...VERIFIED, coachingAgreementAcceptedAt: NOW },
      { role: RoleEnum.coach_l1, activeGrant: true },
    );

    expect(await service.promoteToCoachingIfEligible(1, NOW)).toBe(false);
    expect(roleUpdates).toEqual([]);
  });

  it('should leave a Coaching Partner where they are', async () => {
    const { service, roleUpdates } = serviceWith(
      { ...VERIFIED, coachingAgreementAcceptedAt: NOW },
      { role: RoleEnum.coach_l3, activeGrant: true },
    );

    expect(await service.promoteToCoachingIfEligible(1, NOW)).toBe(false);
    expect(roleUpdates).toEqual([]);
  });
});
