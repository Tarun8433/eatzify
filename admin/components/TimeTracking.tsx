'use client';

import { useEffect, useState } from 'react';
import type { TimeEntry, TrackedTask } from '@/lib/types';
import { hms } from '@/lib/format';
import { GearPathIcon, NodesIcon, PlayIcon } from './icons';

interface Props {
  entry: TimeEntry;
  tasks: TrackedTask[];
}

/**
 * The running timer and the tasks under it.
 *
 * The clock ticks client-side from a seed the server rendered. It deliberately does NOT call
 * `Date.now()` during render — that produces a different string on the server than on the client and
 * React discards the whole tree. The seed renders, then the interval takes over after mount.
 */
export function TimeTracking({ entry, tasks }: Props) {
  const [seconds, setSeconds] = useState(entry.seconds);
  const [running, setRunning] = useState(entry.running);

  useEffect(() => {
    if (!running) return;
    const id = setInterval(() => setSeconds((s) => s + 1), 1000);
    return () => clearInterval(id);
  }, [running]);

  return (
    <section className="card flex min-w-0 flex-col p-4" aria-labelledby="time-tracking-heading">
      <div className="flex items-center justify-between">
        <h2 id="time-tracking-heading" className="text-[14.5px] font-medium text-ink">
          Time tracking
        </h2>
        <button type="button" className="card-menu" aria-label="Time tracking options">
          •••
        </button>
      </div>

      <div className="mt-3.5 flex items-center gap-3 rounded-tile bg-mint p-3.5">
        <div className="min-w-0 flex-1">
          <p className="truncate text-[12.5px] font-medium text-mint-ink/70">{entry.project}</p>
          {/* `tabular-nums` so the digits do not shift width as they count and jog the layout. */}
          <p className="mt-1.5 font-mono text-timer font-semibold tabular-nums text-mint-ink">
            {hms(seconds)}
          </p>
        </div>

        <button
          type="button"
          onClick={() => setRunning((r) => !r)}
          aria-label={running ? 'Pause timer' : 'Start timer'}
          aria-pressed={running}
          className="flex h-[46px] w-[46px] shrink-0 items-center justify-center rounded-full bg-[#101010] text-white transition-transform hover:scale-105"
        >
          {running ? (
            <span className="flex gap-[3px]" aria-hidden>
              <span className="block h-[15px] w-[3.5px] rounded-full bg-white" />
              <span className="block h-[15px] w-[3.5px] rounded-full bg-white" />
            </span>
          ) : (
            <PlayIcon className="ml-0.5 h-[17px] w-[17px]" />
          )}
        </button>
      </div>

      {/*
        The list is clipped by the card rather than scrolled, exactly as the reference shows — the
        third row is half-visible at the foot, which is what tells you the list continues.
      */}
      <ul className="mt-1 min-h-0 flex-1 overflow-hidden">
        {tasks.map((task, i) => {
          const Glyph = task.icon === 'gear' ? GearPathIcon : NodesIcon;
          return (
            <li
              key={task.id}
              className={`flex items-center gap-3 py-3 ${i > 0 ? 'border-t border-line' : ''}`}
            >
              <span className="flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-full bg-raised text-ink">
                <Glyph className="h-[17px] w-[17px]" aria-hidden />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[13px] font-medium text-ink">
                  {task.title}
                </span>
                <span className="block text-[11.5px] tabular-nums text-ink-muted">
                  {hms(task.seconds)}
                </span>
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
