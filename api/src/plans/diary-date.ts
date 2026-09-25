/// The diary day boundary. docs/03 §diary day: a day runs 04:00 IST → 04:00 IST, so a 1 a.m. meal
/// belongs to the previous day rather than starting a new one.
///
/// CLAUDE.md rule 8 puts this on the server precisely so it exists in exactly one place — a client
/// that computed it would drift by timezone, by device clock, and by platform.
const IST_OFFSET_MINUTES = 5 * 60 + 30;
const DAY_STARTS_AT_HOUR = 4;

export function diaryDateFor(instant: Date): string {
  const istMillis = instant.getTime() + IST_OFFSET_MINUTES * 60 * 1000;
  const ist = new Date(istMillis);

  // Before 04:00 IST the diary day is still yesterday.
  if (ist.getUTCHours() < DAY_STARTS_AT_HOUR) {
    ist.setUTCDate(ist.getUTCDate() - 1);
  }

  return ist.toISOString().slice(0, 10);
}

/// The UTC instants a diary date spans: [start, end).
///
/// The inverse of [diaryDateFor], and it exists for the same reason rule 8 exists. A phone syncing
/// steps has to ask HealthKit or Health Connect "how many steps between these two moments", and
/// deriving those moments on the device would put the 04:00 IST boundary in a second place — where
/// it would drift by timezone, by device clock, and by platform, and a 1 a.m. walk would land on
/// the wrong day on some phones and not others.
///
/// So the server sends the window with the day. The client passes it through without arithmetic.
export function diaryWindowFor(diaryDate: string): { start: Date; end: Date } {
  // `diaryDate` is a plain date; 04:00 IST that morning is 22:30 UTC the evening before.
  const midnightUtc = new Date(`${diaryDate}T00:00:00.000Z`);
  const startMillis =
    midnightUtc.getTime() +
    DAY_STARTS_AT_HOUR * 60 * 60 * 1000 -
    IST_OFFSET_MINUTES * 60 * 1000;

  return {
    start: new Date(startMillis),
    end: new Date(startMillis + 24 * 60 * 60 * 1000),
  };
}

/// The last [days] diary days ending with the one [now] falls in, oldest first (D-216).
///
/// For a health-platform backfill, which has to ask the phone about each past day by its window.
/// Only the calendar is walked here — every boundary still comes from [diaryDateFor] and
/// [diaryWindowFor], so this is not a second implementation of rule 4.
export function recentDiaryWindows(
  now: Date,
  days: number,
): { diary_date: string; start: Date; end: Date }[] {
  const today = new Date(`${diaryDateFor(now)}T00:00:00.000Z`);

  return Array.from({ length: days }, (_, i) => {
    const date = new Date(today);
    date.setUTCDate(today.getUTCDate() - (days - 1 - i));
    const diaryDate = date.toISOString().slice(0, 10);
    return { diary_date: diaryDate, ...diaryWindowFor(diaryDate) };
  });
}
