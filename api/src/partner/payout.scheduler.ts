import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PayoutService } from './payout.service';
import { previousPeriod } from './payout-rules';

/// docs/12 §5: "Cycle: monthly, on the 1st, for the previous calendar month's payable balance."
/// 06:00 IST on the 1st.
export const PAYOUT_RUN_CRON = '0 6 1 * *';

/// docs/12 §4: the reconciliation invariant, "asserted nightly". 05:00 IST.
export const RECONCILE_CRON = '0 5 * * *';

/// The clock, and nothing else. Both jobs are also reachable from the admin payout desk.
@Injectable()
export class PayoutScheduler {
  private readonly log = new Logger(PayoutScheduler.name);

  constructor(private readonly payouts: PayoutService) {}

  @Cron(PAYOUT_RUN_CRON, { name: 'payout-run', timeZone: 'Asia/Kolkata' })
  async monthly(): Promise<void> {
    const now = new Date();
    try {
      const report = await this.payouts.prepare(previousPeriod(now), now);
      // Counts only (api rule 5).
      this.log.log(
        `payout run ${report.period}: ${report.prepared} prepared, skipped ${JSON.stringify(report.skipped)}`,
      );
    } catch (e) {
      // Most likely no TDS rate yet. Loud, because partners are waiting on it.
      this.log.error(
        `payout run failed: ${e instanceof Error ? e.message : 'unknown'}`,
      );
    }
  }

  @Cron(RECONCILE_CRON, { name: 'payout-reconcile', timeZone: 'Asia/Kolkata' })
  async nightly(): Promise<void> {
    await this.payouts.reconcile();
  }
}
