import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrivacySweepService } from './privacy-sweep.service';

/// 04:15 IST — after the subscription sweep, and outside the hours anyone is using the app. A
/// notice that says "your account disappears in 48 hours" should not land during dinner.
export const PRIVACY_SWEEP_CRON = '15 22 * * *';

/// The clock, and nothing else. The work is [PrivacySweepService], which a test — or an operator
/// answering a regulator — can run on demand.
@Injectable()
export class PrivacyScheduler {
  private readonly log = new Logger(PrivacyScheduler.name);

  constructor(private readonly sweep: PrivacySweepService) {}

  @Cron(PRIVACY_SWEEP_CRON, { name: 'privacy-sweep', timeZone: 'Asia/Kolkata' })
  async daily(): Promise<void> {
    const report = await this.sweep.run(new Date());
    // Counts only (api rule 5).
    this.log.log(
      `privacy sweep: ${report.notified} notified, ${report.erased} erased`,
    );
  }
}
