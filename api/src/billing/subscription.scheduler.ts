import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { SubscriptionSweepService } from './subscription-sweep.service';

/// When the daily pass runs: 03:30 IST, which is 22:00 UTC. Before the 04:00 IST diary boundary and
/// well outside the hours anyone is logging food, so a notice never lands mid-meal.
export const SWEEP_CRON = '0 22 * * *';

/// The clock, and nothing else. The work is [SubscriptionSweepService], which a test — or an
/// operator at a console — can run without waiting for tomorrow.
@Injectable()
export class SubscriptionScheduler {
  private readonly log = new Logger(SubscriptionScheduler.name);

  constructor(private readonly sweep: SubscriptionSweepService) {}

  @Cron(SWEEP_CRON, { name: 'subscription-sweep', timeZone: 'Asia/Kolkata' })
  async daily(): Promise<void> {
    const report = await this.sweep.run(new Date());
    // Counts only: no user id, no amount, nothing that identifies anybody (api rule 5).
    this.log.log(
      `subscription sweep: ${report.checked} checked, ${report.notices} notices, ${report.moved} moved`,
    );
  }
}
