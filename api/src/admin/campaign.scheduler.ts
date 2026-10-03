import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AdminCampaignsService } from './admin-campaigns.service';

/// Sends scheduled messages when they come due (admin panel plan, Phase C). Kept apart from the
/// service, as the subscription sweep is, so unit tests never load the scheduler package.
@Injectable()
export class CampaignScheduler {
  private readonly log = new Logger(CampaignScheduler.name);

  constructor(private readonly campaigns: AdminCampaignsService) {}

  @Cron(CronExpression.EVERY_MINUTE, { name: 'campaigns' })
  async tick(): Promise<void> {
    const sent = await this.campaigns.runDue(new Date());
    if (sent) this.log.log(`sent ${sent} scheduled campaign(s)`);
  }
}
