import Image from 'next/image';
import { longDate } from '@/lib/format';
import { BellIcon, ChevronDownIcon, FilterIcon, SearchIcon, SunIcon } from './icons';

interface Props {
  viewer: { name: string; role: string; photoUrl: string };
  tempC: number;
  /** Passed in rather than read from the clock here, so the server and client render the same
   *  string — `new Date()` in a component is the classic hydration mismatch. */
  today: string;
  query: string;
  onQueryChange: (value: string) => void;
}

export function TopBar({ viewer, tempC, today, query, onQueryChange }: Props) {
  return (
    <header className="flex shrink-0 items-start justify-between gap-6 pt-5">
      <div>
        <p className="text-[12.5px] text-ink-muted">{today}</p>
        <p className="mt-1 flex items-center gap-1.5 text-[15px] font-medium text-ink">
          <SunIcon className="h-[18px] w-[18px]" aria-hidden />
          {tempC}°C
        </p>
      </div>

      {/* Centred on the shell, not on the space left over — the reference keeps it on the page's
          axis regardless of how long the name on the right is. */}
      <div className="mt-1 w-full max-w-[460px]">
        <label className="sr-only" htmlFor="global-search">
          Search
        </label>
        <div className="flex h-[42px] items-center gap-2.5 rounded-full bg-raised px-4">
          <SearchIcon className="h-[17px] w-[17px] shrink-0 text-ink-muted" aria-hidden />
          <input
            id="global-search"
            type="search"
            value={query}
            onChange={(e) => onQueryChange(e.target.value)}
            placeholder="Search"
            className="min-w-0 flex-1 bg-transparent text-[13.5px] text-ink placeholder:text-ink-muted focus:outline-none"
          />
          <button
            type="button"
            aria-label="Search filters"
            className="shrink-0 text-ink-muted transition-colors hover:text-ink"
          >
            <FilterIcon className="h-[17px] w-[17px]" />
          </button>
        </div>
      </div>

      <div className="mt-0.5 flex items-center gap-3">
        <button
          type="button"
          aria-label="Notifications"
          className="flex h-[42px] w-[42px] items-center justify-center rounded-full bg-raised text-ink transition-colors hover:bg-line"
        >
          <BellIcon className="h-[18px] w-[18px]" />
        </button>

        <button type="button" className="flex items-center gap-2.5 text-left">
          <Image
            src={viewer.photoUrl}
            alt=""
            width={42}
            height={42}
            className="h-[42px] w-[42px] rounded-full object-cover"
          />
          <span className="hidden leading-tight sm:block">
            <span className="block text-[13.5px] font-medium text-ink">{viewer.name}</span>
            <span className="block text-[11.5px] text-ink-muted">{viewer.role}</span>
          </span>
          <ChevronDownIcon className="h-4 w-4 text-ink-muted" aria-hidden />
        </button>
      </div>
    </header>
  );
}
