import { diaryDateFor, diaryWindowFor } from '../src/plans/diary-date';

/// D-98. The window the client uses to ask a phone for a day's steps. It has to be the exact
/// inverse of `diaryDateFor` or a sync files a walk under the wrong day — invisibly, because both
/// days look plausible.
describe('diaryWindowFor', () => {
  it('starts at 04:00 IST, which is 22:30 UTC the evening before', () => {
    const { start } = diaryWindowFor('2026-08-31');
    expect(start.toISOString()).toBe('2026-08-30T22:30:00.000Z');
  });

  it('spans exactly 24 hours', () => {
    const { start, end } = diaryWindowFor('2026-08-31');
    expect(end.getTime() - start.getTime()).toBe(24 * 60 * 60 * 1000);
  });

  it('round-trips: every instant in the window belongs to that diary date', () => {
    const date = '2026-08-31';
    const { start, end } = diaryWindowFor(date);

    // The first instant, the last, and a scatter in between.
    const probes = [
      start,
      new Date(start.getTime() + 1),
      new Date(start.getTime() + 12 * 60 * 60 * 1000),
      new Date(end.getTime() - 1),
    ];

    for (const probe of probes) {
      expect(diaryDateFor(probe)).toBe(date);
    }
  });

  it('excludes its end, which is the next day', () => {
    const { end } = diaryWindowFor('2026-08-31');
    expect(diaryDateFor(end)).toBe('2026-09-01');
  });

  it('puts a 1 a.m. IST walk on the previous day, both ways', () => {
    // 01:00 IST on 1 Sep is 19:30 UTC on 31 Aug, and belongs to the 31st.
    const oneAm = new Date('2026-08-31T19:30:00.000Z');
    expect(diaryDateFor(oneAm)).toBe('2026-08-31');

    const { start, end } = diaryWindowFor('2026-08-31');
    expect(oneAm.getTime()).toBeGreaterThanOrEqual(start.getTime());
    expect(oneAm.getTime()).toBeLessThan(end.getTime());
  });

  it('handles a month boundary', () => {
    const { start } = diaryWindowFor('2026-09-01');
    expect(start.toISOString()).toBe('2026-08-31T22:30:00.000Z');
    expect(diaryDateFor(start)).toBe('2026-09-01');
  });
});
