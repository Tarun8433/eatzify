import Image from 'next/image';
import type { ScheduledTask } from '@/lib/types';
import { DownloadIcon, SearchIcon } from './icons';

interface Props {
  tasks: ScheduledTask[];
  days: { label: string; date: number }[];
  /** Index of today's column — filled mint in the reference. */
  todayIndex: number;
}

/// The visible window. The reference shows 12:00 to 18:00 and nothing outside it.
const START_HOUR = 12;
const END_HOUR = 18;
const HOURS = Array.from({ length: END_HOUR - START_HOUR + 1 }, (_, i) => START_HOUR + i);

/// How many day columns a task block spans. The reference's blocks overhang their own day
/// rather than being clipped to it; at 2.1 the titles ellipsised to "Tea...", which is the one
/// thing a task block must never do.
const BLOCK_COLUMNS = 2.75;

export function TasksOverview({ tasks, days, todayIndex }: Props) {
  const span = END_HOUR - START_HOUR;

  return (
    <section className="card flex min-w-0 flex-col p-4" aria-labelledby="tasks-heading">
      <div className="flex items-center justify-between">
        <h2 id="tasks-heading" className="text-[14.5px] font-medium text-ink">
          Tasks overview
        </h2>
        <div className="flex items-center gap-1">
          <button type="button" className="card-menu" aria-label="Search tasks">
            <SearchIcon className="h-[17px] w-[17px]" />
          </button>
          <button type="button" className="card-menu" aria-label="Export tasks">
            <DownloadIcon className="h-[17px] w-[17px]" />
          </button>
        </div>
      </div>

      {/* One grid for the header and one for the body, sharing a column template so the day columns
          and the task lanes line up exactly. A single grid cannot do it — the hour gutter is a fixed
          width and the day columns are fractional. */}
      <div className="mt-3 grid grid-cols-[46px_repeat(7,1fr)] gap-x-1">
        <span />
        {days.map((d, i) => (
          <div key={d.label} className="flex justify-center">
            <div
              className={`flex w-full max-w-[62px] flex-col items-center rounded-tile py-1.5 ${
                i === todayIndex ? 'bg-mint text-mint-ink' : 'text-ink-muted'
              }`}
            >
              <span className="text-[12.5px] font-medium">{d.label}</span>
              <span
                className={`mt-0.5 text-[12px] ${
                  i === todayIndex ? 'font-semibold' : 'text-ink-faint'
                }`}
              >
                {d.date}
              </span>
            </div>
          </div>
        ))}
      </div>

      <div className="relative mt-2 min-h-[260px] flex-1">
        {/* Hour rows: label in the gutter, a hairline across the lanes. */}
        <div className="absolute inset-0 grid grid-cols-[46px_1fr]">
          <div className="relative">
            {HOURS.map((h, i) => (
              <span
                key={h}
                className="absolute left-0 -translate-y-1/2 text-[11.5px] text-ink-muted"
                style={{ top: `${(i / span) * 100}%` }}
              >
                {String(h).padStart(2, '0')}:00
              </span>
            ))}
          </div>
          <div />
        </div>

        {/* The seven vertical day separators, dashed as in the reference. */}
        <div
          aria-hidden
          className="absolute inset-y-0 left-[46px] right-0 grid grid-cols-7 gap-x-1"
        >
          {days.map((d) => (
            <span key={d.label} className="border-l border-dashed border-line/70" />
          ))}
        </div>

        {/* Task blocks, positioned by time and day. Absolute against the same box the separators
            use, so a block's left edge is its day's left edge by construction. */}
        <div className="absolute inset-y-0 left-[46px] right-0">
          {tasks.map((task) => {
            const top = ((task.startHour - START_HOUR) / span) * 100;
            const height = ((task.endHour - task.startHour) / span) * 100;
            // Clamped to the lane, so a block late in the week is nudged left instead of running
            // off the card and losing its own attendees to the overflow.
            const widthPct = (BLOCK_COLUMNS / 7) * 100;
            const left = Math.min((task.dayIndex / 7) * 100, 100 - widthPct);

            return (
              <article
                key={task.id}
                style={{
                  top: `${top}%`,
                  height: `${height}%`,
                  left: `${left}%`,
                  width: `${widthPct}%`,
                }}
                className={`absolute flex items-center gap-2 overflow-hidden rounded-tile px-3 py-2 ${
                  task.highlighted ? 'bg-mint text-mint-ink' : 'bg-raised text-ink'
                }`}
              >
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[12.5px] font-semibold">{task.title}</span>
                  <span
                    className={`block truncate text-[11.5px] ${
                      task.highlighted ? 'text-mint-ink/70' : 'text-ink-muted'
                    }`}
                  >
                    {task.subtitle}
                  </span>
                </span>

                <span className="flex shrink-0 -space-x-2">
                  {task.attendees.slice(0, 5).map((src, i) => (
                    <Image
                      key={i}
                      src={src}
                      alt=""
                      width={24}
                      height={24}
                      className={`h-6 w-6 rounded-full object-cover ring-2 ${
                        task.highlighted ? 'ring-mint' : 'ring-raised'
                      }`}
                    />
                  ))}
                </span>
              </article>
            );
          })}
        </div>
      </div>
    </section>
  );
}
