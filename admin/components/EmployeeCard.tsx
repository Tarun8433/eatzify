import Image from 'next/image';
import type { Employee } from '@/lib/types';
import { MailIcon, PhoneIcon } from './icons';

/**
 * The employee's photo with a floating identity bar across its foot.
 *
 * The bar is a separate dark panel ON the photo rather than a gradient over it — the reference's bar
 * has its own corners and its own two buttons, and a gradient could not hold a button legibly
 * against an arbitrary photograph.
 */
export function EmployeeCard({ employee }: { employee: Employee }) {
  return (
    <article className="relative overflow-hidden rounded-card">
      <Image
        src={employee.photoUrl}
        alt={employee.name}
        width={560}
        height={640}
        priority
        className="h-[330px] w-full object-cover"
      />

      <div className="absolute inset-x-2.5 bottom-2.5 flex items-center gap-2 rounded-tile bg-[#161616]/95 px-3.5 py-3 backdrop-blur-sm">
        <div className="min-w-0 flex-1">
          <p className="truncate text-[15px] font-semibold text-ink">{employee.name}</p>
          <p className="truncate text-[12px] text-ink-muted">{employee.role}</p>
        </div>

        <button
          type="button"
          aria-label={`Call ${employee.name}`}
          className="flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-full bg-raised text-ink transition-colors hover:bg-line"
        >
          <PhoneIcon className="h-[17px] w-[17px]" />
        </button>
        <button
          type="button"
          aria-label={`Email ${employee.name}`}
          className="flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-full bg-mint text-mint-ink transition-opacity hover:opacity-90"
        >
          <MailIcon className="h-[17px] w-[17px]" />
        </button>
      </div>
    </article>
  );
}
