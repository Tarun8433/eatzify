'use client';

import Image from 'next/image';
import type { TeamMember } from '@/lib/types';
import { ChevronLeftIcon, ChevronRightIcon, PlusIcon } from './icons';

interface Props {
  name: string;
  department: string;
  memberCount: number;
  members: TeamMember[];
  /** Which avatar is selected — ringed in the reference. */
  activeMemberId: number;
  onSelect: (id: number) => void;
}

export function TeamHeader({
  name,
  department,
  memberCount,
  members,
  activeMemberId,
  onSelect,
}: Props) {
  return (
    <div className="flex shrink-0 items-center justify-between gap-6 py-4">
      <div>
        <h1 className="text-[21px] font-semibold leading-tight tracking-[-0.01em] text-ink">
          {name} <span className="text-ink-muted">·</span> {department}
        </h1>
        <p className="mt-0.5 text-[12.5px] text-ink-muted">{memberCount} members</p>
      </div>

      <div className="flex items-center gap-2.5">
        <button
          type="button"
          aria-label="Previous members"
          className="flex h-[34px] w-[34px] items-center justify-center rounded-full border border-line text-ink-muted transition-colors hover:text-ink"
        >
          <ChevronLeftIcon className="h-4 w-4" />
        </button>

        <ul className="flex items-center gap-2">
          {members.map((m) => {
            const isActive = m.id === activeMemberId;
            return (
              <li key={m.id}>
                <button
                  type="button"
                  onClick={() => onSelect(m.id)}
                  aria-label={m.name}
                  aria-pressed={isActive}
                  title={m.name}
                  // The ring is drawn with a gap so the avatar is circled rather than outlined —
                  // an outline touching the photo reads as a border on the image itself.
                  className={`block rounded-full transition-shadow ${
                    isActive
                      ? 'ring-2 ring-white ring-offset-[3px] ring-offset-shell'
                      : 'hover:ring-2 hover:ring-line hover:ring-offset-[3px] hover:ring-offset-shell'
                  }`}
                >
                  <Image
                    src={m.photoUrl}
                    alt=""
                    width={40}
                    height={40}
                    className="h-10 w-10 rounded-full object-cover"
                  />
                </button>
              </li>
            );
          })}
        </ul>

        <button
          type="button"
          aria-label="Next members"
          className="flex h-[34px] w-[34px] items-center justify-center rounded-full border border-line text-ink-muted transition-colors hover:text-ink"
        >
          <ChevronRightIcon className="h-4 w-4" />
        </button>
      </div>

      <button
        type="button"
        className="flex h-[42px] items-center gap-2 rounded-full bg-raised px-5 text-[13.5px] font-medium text-ink transition-colors hover:bg-line"
      >
        <PlusIcon className="h-[17px] w-[17px]" aria-hidden />
        Add employee
      </button>
    </div>
  );
}
