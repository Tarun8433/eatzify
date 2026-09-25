/**
 * Formatting, in one place.
 *
 * Numbers stay arithmetic until the moment they are displayed — a component that receives
 * `"03:37:52"` cannot add to it, and one that receives `485000` cannot accidentally render paise as
 * dollars. Every conversion the dashboard needs is here and nowhere else.
 */

/// `13072` → `03:37:52`. Always two digits per part, because a timer whose width changes as it
/// counts makes the whole card twitch.
export function hms(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds));
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(Math.floor(s / 3600))}:${pad(Math.floor((s % 3600) / 60))}:${pad(s % 60)}`;
}

/// Money arrives as an integer minor unit (`api/CLAUDE.md` rule 3) and is only ever divided here.
export function money(minor: number, currency: string): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
    maximumFractionDigits: 0,
  }).format(minor / 100);
}

/**
 * "Wednesday, 18 Sep", exactly as the reference prints it.
 *
 * Assembled rather than handed to one `Intl.DateTimeFormat` call: the combined format drops the
 * comma and, on current ICU, abbreviates September to "Sept" rather than "Sep". Each part is
 * formatted on its own and joined here, so the punctuation is ours.
 */
export function longDate(date: Date): string {
  const weekday = new Intl.DateTimeFormat('en-GB', { weekday: 'long' }).format(date);
  const day = new Intl.DateTimeFormat('en-GB', { day: 'numeric' }).format(date);
  // `month: 'short'` yields "Sept"; slicing to three characters gives the reference's "Sep".
  const month = new Intl.DateTimeFormat('en-GB', { month: 'long' }).format(date).slice(0, 3);
  return `${weekday}, ${day} ${month}`;
}

/**
 * The stroke geometry for a ring showing `pct`.
 *
 * Returns the dash pair for a circle of radius `r`, so a ring is one `<circle>` with a computed
 * `strokeDasharray` rather than an arc path — no trigonometry, and it cannot produce the wrong sweep
 * direction. Clamped, because a percentage over 100 would wrap the ring back past its own start and
 * silently read as a smaller number.
 */
export function ringDash(pct: number, r: number): { dash: number; gap: number } {
  const circumference = 2 * Math.PI * r;
  const filled = (Math.min(100, Math.max(0, pct)) / 100) * circumference;
  return { dash: filled, gap: circumference - filled };
}
