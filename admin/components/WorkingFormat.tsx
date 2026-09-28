import type { WorkingFormat as Format } from '@/lib/types';
import { ringDash } from '@/lib/format';

/**
 * Three concentric arcs, one per working format, with the day count in the middle.
 *
 * Concentric rather than a stacked donut because the reference shows three SEPARATE tracks — a
 * stacked ring would put the three shares end to end on one circle, which answers a different
 * question ("how is the whole split?") than three tracks do ("how much of each?").
 *
 * Each ring is a full circle with a dash pattern rather than an arc path: no trigonometry, no
 * chance of the sweep flipping direction, and the rotation puts every ring's start at 12 o'clock.
 */
export function WorkingFormat({ format }: { format: Format }) {
  const rings = [
    { pct: format.officePct, r: 62, color: '#ffffff', label: 'Office' },
    { pct: format.hybridPct, r: 50, color: '#7fd7e3', label: 'Hybrid' },
    { pct: format.remotePct, r: 38, color: '#4aa8c4', label: 'Remote' },
  ];

  return (
    <section className="card flex min-w-0 flex-col p-4" aria-labelledby="working-format-heading">
      <div className="flex items-center justify-between">
        <h2 id="working-format-heading" className="text-[14.5px] font-medium text-ink">
          Working format
        </h2>
        <button type="button" className="card-menu" aria-label="Working format options">
          •••
        </button>
      </div>

      <div className="relative mx-auto my-1 flex h-[178px] w-[178px] items-center justify-center">
        <svg viewBox="0 0 160 160" className="h-full w-full -rotate-90">
          {rings.map(({ pct, r, color, label }) => {
            const { dash, gap } = ringDash(pct, r);
            return (
              <g key={label}>
                {/* The unfilled track. Without it a short arc floats with nothing to measure it. */}
                <circle cx="80" cy="80" r={r} fill="none" stroke="#2b2b2b" strokeWidth="9" />
                <circle
                  cx="80"
                  cy="80"
                  r={r}
                  fill="none"
                  stroke={color}
                  strokeWidth="9"
                  strokeLinecap="round"
                  strokeDasharray={`${dash} ${gap}`}
                />
              </g>
            );
          })}
        </svg>

        <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-[30px] font-semibold leading-none text-ink">
            {format.totalDays}
          </span>
          <span className="mt-1 text-[12px] text-ink-muted">Days</span>
        </div>
      </div>

      <ul className="mt-auto flex items-start justify-between px-1 pt-2">
        {rings.map(({ pct, color, label }) => (
          <li key={label} className="flex flex-col items-center gap-1">
            <span className="flex items-center gap-1.5">
              <span
                aria-hidden
                className="block h-[7px] w-[7px] rounded-full"
                style={{ backgroundColor: color }}
              />
              <span className="text-[13px] font-medium text-ink">{pct}%</span>
            </span>
            <span className="text-[11.5px] text-ink-muted">{label}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}
