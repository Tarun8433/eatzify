import {
  DELETE_COOLING_OFF_DAYS,
  ERASURE_NOTICE_HOURS,
  EXPORT_LINK_HOURS,
  RETENTION_DAYS,
  addDays,
  addHours,
  erasureDue,
  erasureDueAt,
  exportExpiresAt,
  noticeDue,
  retentionCutoff,
} from '../src/privacy/privacy-rules';

/// docs/13 §6 and §9. These are dates the law puts on a right, so the tests read them back from the
/// document rather than from the implementation.

const REQUESTED = new Date('2026-09-18T10:00:00Z');

describe('the numbers docs/13 fixes', () => {
  it('should hold the published periods', () => {
    expect(DELETE_COOLING_OFF_DAYS).toBe(7);
    expect(ERASURE_NOTICE_HOURS).toBe(48);
    expect(EXPORT_LINK_HOURS).toBe(24);
    expect(RETENTION_DAYS.mealPhotos).toBe(90);
    expect(RETENTION_DAYS.screening).toBe(365);
    expect(RETENTION_DAYS.healthAfterInactivity).toBe(3 * 365);
    expect(RETENTION_DAYS.ticketsAfterClosure).toBe(2 * 365);
    expect(RETENTION_DAYS.accountAfterDeletion).toBe(30);
  });
});

describe('erasure, from asked to done (docs/13 §9)', () => {
  it('should not run before the cooling-off has passed', () => {
    const due = erasureDueAt(REQUESTED);

    expect(due).toEqual(addDays(REQUESTED, 7));
    expect(
      erasureDue(
        { executeAfter: due, notifiedAt: REQUESTED },
        addDays(REQUESTED, 6),
      ),
    ).toBe(false);
  });

  it('should owe the warning 48 hours before it is due, not before', () => {
    const due = erasureDueAt(REQUESTED);

    expect(noticeDue(due, addDays(REQUESTED, 4))).toBe(false);
    expect(noticeDue(due, addHours(due, -47))).toBe(true);
  });

  /// A person warned two hours before deletion was not warned.
  it('should refuse to run until 48 hours after the warning actually went out', () => {
    const due = erasureDueAt(REQUESTED);
    const lateNotice = addHours(due, -2);

    expect(erasureDue({ executeAfter: due, notifiedAt: lateNotice }, due)).toBe(
      false,
    );
    expect(
      erasureDue(
        { executeAfter: due, notifiedAt: lateNotice },
        addHours(lateNotice, 48),
      ),
    ).toBe(true);
  });

  it('should never run when no warning was sent at all', () => {
    const due = erasureDueAt(REQUESTED);

    expect(
      erasureDue(
        { executeAfter: due, notifiedAt: null },
        addDays(REQUESTED, 30),
      ),
    ).toBe(false);
  });
});

describe('the export link', () => {
  it('should stop working a day after it was built', () => {
    expect(exportExpiresAt(REQUESTED)).toEqual(addHours(REQUESTED, 24));
  });
});

describe('the retention cut-off', () => {
  it('should look backwards, not forwards', () => {
    expect(retentionCutoff(REQUESTED, 90)).toEqual(addDays(REQUESTED, -90));
  });
});
