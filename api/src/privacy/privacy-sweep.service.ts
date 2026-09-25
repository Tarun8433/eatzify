import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { PrivacyRequestEntity } from './entities/privacy-request.entity';
import { erasureDue, noticeDue } from './privacy-rules';
import { PrivacyService } from './privacy.service';
import { NotificationsService } from '../notifications/notifications.service';

export type SweepResult = {
  notified: number;
  erased: number;
};

/**
 * The half of docs/13 §9 that happens without anybody pressing anything.
 *
 * Two steps, in this order and never merged: warn 48 hours ahead, then erase. Merging them would
 * make the warning a receipt rather than a chance to stop, which is the opposite of what the Rules
 * ask for — and it is why `erasureDue` refuses to run until 48 hours after the notice actually went
 * out, not merely 48 hours after it was due.
 */
@Injectable()
export class PrivacySweepService {
  private readonly log = new Logger(PrivacySweepService.name);

  constructor(
    @InjectRepository(PrivacyRequestEntity)
    private readonly requests: Repository<PrivacyRequestEntity>,
    private readonly privacy: PrivacyService,
    private readonly notifications: NotificationsService,
  ) {}

  async run(now = new Date()): Promise<SweepResult> {
    const open = await this.requests.find({
      where: { kind: 'delete', status: In(['pending', 'notified']) },
      order: { executeAfter: 'ASC' },
      take: 500,
    });

    let notified = 0;
    let erased = 0;

    for (const request of open) {
      if (
        request.status === 'pending' &&
        noticeDue(request.executeAfter, now)
      ) {
        await this.warn(request, now);
        notified += 1;
        continue;
      }

      if (erasureDue(request, now)) {
        // No PII in the line, per api rule 5 — an id and a count is the whole log entry.
        await this.privacy.erase(request.userId, now);
        this.log.log(`erased account ${request.userId}`);
        erased += 1;
      }
    }

    return { notified, erased };
  }

  private async warn(request: PrivacyRequestEntity, now: Date): Promise<void> {
    await this.notifications.notify({
      userId: request.userId,
      kind: 'account_deletion_imminent',
      contentClass: 'service',
      title: 'Your account will be deleted in 48 hours',
      body: 'If you want to keep it, open the app and stop the deletion. After that your health data is gone for good.',
      data: { request_id: request.id },
      // The one notice that has to arrive even if the app is never opened again.
      alsoEmail: true,
      dedupeKey: `deletion_notice:${request.id}`,
    });

    request.status = 'notified';
    request.notifiedAt = now;
    await this.requests.save(request);
  }
}
