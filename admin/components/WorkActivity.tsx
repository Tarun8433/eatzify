import type { ActivityBucket, WorkActivity as Activity } from '@/lib/types';
import { CalendarIcon } from './icons';

/// Four states, matching the legend exactly. A fifth shade would make the grid unreadable at this
/// cell size, which is why the reference defines four and stops.
const BUCKET_CLASS: Record<ActivityBucket, string> = {
  0: 'cell-empty',
  1: 'bg-[#4a4a4a]',
  2: 'bg-[#8f9a97]',
  3: 'bg-mint-bright',
};

const LEGEND: { bucket: ActivityBucket; label: string }[] = [
  { bucket: 0, label: '0h' },
  { bucket: 1, label: '>2h' },
  { bucket: 2, label: '>4h' },
  { bucket: 3, label: '>8h' },
];

export function WorkActivity({ activity }: { activity: Activity }) {
  return (
    <section className="card p-4" aria-labelledby="work-activity-heading">
      <div className="flex items-center justify-between gap-2">
        <div className="flex min-w-0 items-center gap-2">
          <h2 id="work-activity-heading" className="text-[14.5px] font-medium text-ink">
            Work activity
          </h2>
          <span className="shrink-0 rounded-full bg-mint px-2.5 py-[3px] text-[11px] font-medium text-mint-ink">
            ~{activity.totalHours}h • {activity.averagePct}% Avg
          </span>
        </div>
        <button type="button" className="card-menu shrink-0" aria-label="Choose date range">
          <CalendarIcon className="h-[17px] w-[17px]" />
        </button>
      </div>

      <ul className="mt-3 flex items-center gap-3">
        {LEGEND.map(({ bucket, label }) => (
          <li key={label} className="flex items-center gap-1.5">
            <span
              aria-hidden
              className={`block h-[9px] w-[9px] rounded-[2px] ${BUCKET_CLASS[bucket]}`}
            />
            <span className="text-[11px] text-ink-muted">{label}</span>
          </li>
        ))}
      </ul>

      {/*
        A table, not a div grid. This is a matrix of hours against days and a screen reader needs the
        row and column headers to say what any given cell means — "3 cells filled" is not a reading
        of this widget.
      */}
      <table className="mt-3 w-full border-separate border-spacing-[5px]">
        <caption className="sr-only">
          Hours worked per hour of the day across the week
        </caption>
        <thead>
          <tr>
            <th />
            {activity.dayLabels.map((d) => (
              <th key={d} scope="col" className="pb-1 text-[11px] font-normal text-ink-muted">
                {d}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {activity.cells.map((row, rowIndex) => (
            <tr key={activity.hourLabels[rowIndex]}>
              <th
                scope="row"
                className="pr-1 text-right align-middle text-[11px] font-normal text-ink-muted"
              >
                {activity.hourLabels[rowIndex]}
              </th>
              {row.map((bucket, colIndex) => (
                <td key={`${rowIndex}-${colIndex}`}>
                  <span
                    title={`${activity.dayLabels[colIndex]} ${activity.hourLabels[rowIndex]}: ${
                      LEGEND[bucket].label
                    }`}
                    className={`block h-[26px] w-full rounded-[7px] ${BUCKET_CLASS[bucket]}`}
                  />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
