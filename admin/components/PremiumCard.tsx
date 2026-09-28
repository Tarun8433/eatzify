import { ArrowRightIcon } from './icons';

/**
 * The upsell — Eatzify's own tiers (docs/11), not an HR product's. The only mint-filled card in the
 * left column, which is what makes it the thing your eye lands on last and remembers.
 */
export function PremiumCard({ pricePerMonth }: { pricePerMonth: string }) {
  return (
    <article className="rounded-card bg-mint p-4 text-mint-ink">
      <div className="flex items-center justify-between">
        <span className="flex h-[38px] w-[38px] items-center justify-center rounded-full bg-black/10">
          <span className="block h-3.5 w-3.5 rounded-full border-[3px] border-mint-ink" />
        </span>

        <button
          type="button"
          className="flex items-center gap-2.5 rounded-full bg-white/70 py-2 pl-4 pr-2.5 text-[13px] font-semibold transition-colors hover:bg-white"
        >
          {pricePerMonth}
          <ArrowRightIcon className="h-4 w-4" aria-hidden />
        </button>
      </div>

      <h3 className="mt-8 text-[24px] font-semibold leading-tight tracking-[-0.01em]">
        Eatzify PRO
      </h3>
      <p className="mt-1 text-[12.5px] opacity-70">Unlimited plans, coach chat &amp; deeper insights</p>
    </article>
  );
}
