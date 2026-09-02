import { diaryDateFor } from '../src/plans/diary-date';

/// docs/03: the diary day runs 04:00 IST → 04:00 IST. CLAUDE.md rule 8 keeps this server-side so it
/// exists in one place — a client would drift by timezone, device clock and platform.
describe('diary date — the 04:00 IST boundary', () => {
  it('a 1 a.m. IST meal still belongs to the previous day', () => {
    // 2026-08-25T01:30 IST === 2026-08-24T20:00Z
    expect(diaryDateFor(new Date('2026-08-24T20:00:00Z'))).toBe('2026-08-24');
  });

  it('04:00 IST starts the new day', () => {
    // 2026-08-25T04:00 IST === 2026-08-24T22:30Z
    expect(diaryDateFor(new Date('2026-08-24T22:30:00Z'))).toBe('2026-08-25');
  });

  it('03:59 IST is still the day before', () => {
    expect(diaryDateFor(new Date('2026-08-24T22:29:00Z'))).toBe('2026-08-24');
  });

  it('midday IST is that day', () => {
    // 2026-08-25T12:00 IST === 2026-08-25T06:30Z
    expect(diaryDateFor(new Date('2026-08-25T06:30:00Z'))).toBe('2026-08-25');
  });

  it('rolls the month correctly across the boundary', () => {
    // 2026-09-01T02:00 IST === 2026-08-31T20:30Z → still August 31
    expect(diaryDateFor(new Date('2026-08-31T20:30:00Z'))).toBe('2026-08-31');
  });
});
