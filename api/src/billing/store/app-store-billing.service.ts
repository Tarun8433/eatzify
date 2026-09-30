import { Injectable, Logger } from '@nestjs/common';
import { VerificationException } from '@apple/app-store-server-library';
import { AppStoreClient } from './app-store.client';
import { PlayBillingService } from './play-billing.service';
import { StoreGrantService } from './store-grant.service';
import {
  purchaseNotActive,
  purchaseOtherAccount,
  storeNotConfigured,
} from './store-errors';
import { grantFromAppStore, type StoreGrant } from './store-rules';

/// App Store purchases (payments plan, Phase 5), the same shape as Play: the app hands over what
/// StoreKit gave it, the server checks Apple's signature, re-reads the subscription from Apple,
/// and only then touches the account (docs/11 §5, rule 3).
@Injectable()
export class AppStoreBillingService {
  private readonly log = new Logger(AppStoreBillingService.name);

  constructor(
    private readonly apple: AppStoreClient,
    private readonly grants: StoreGrantService,
    // The account token is one function for both stores; Play's service already owns it.
    private readonly play: PlayBillingService,
  ) {}

  /// `POST /billing/appstore/verify`, straight after a purchase on the phone. [jws] is StoreKit 2's
  /// `jwsRepresentation` of the transaction.
  async verify(userId: number, jws: string, now: Date): Promise<void> {
    if (!this.apple.configured) throw storeNotConfigured();

    let originalTransactionId: string | undefined;
    try {
      originalTransactionId = (await this.apple.verifyTransaction(jws))
        .originalTransactionId;
    } catch (e) {
      // Forged, for another app, or the wrong environment: nothing was bought here.
      if (e instanceof VerificationException) throw purchaseNotActive();
      throw e;
    }
    const grant = originalTransactionId
      ? await this.grantFor(originalTransactionId)
      : null;
    if (!grant || grant.status === 'expired') throw purchaseNotActive();

    if (
      grant.accountToken &&
      grant.accountToken !== this.play.accountToken(userId)
    ) {
      throw purchaseOtherAccount();
    }
    await this.grants.apply(userId, grant, now);
  }

  /// App Store Server Notifications v2. The payload is signed by Apple and checked, and the
  /// subscription is still re-read from Apple before anything changes.
  async notification(signedPayload: string, now: Date): Promise<void> {
    if (!this.apple.configured) return;

    let signedTransaction: string | undefined;
    try {
      const note = await this.apple.verifyNotification(signedPayload);
      signedTransaction = note.data?.signedTransactionInfo;
    } catch (e) {
      if (e instanceof VerificationException) {
        this.log.warn(`rejected App Store notification: status ${e.status}`);
        return;
      }
      throw e;
    }
    if (!signedTransaction) return;

    const tx = await this.apple.verifyTransaction(signedTransaction);
    if (!tx.originalTransactionId) return;
    const grant = await this.grantFor(tx.originalTransactionId);
    if (grant) await this.grants.apply(null, grant, now);
  }

  private async grantFor(
    originalTransactionId: string,
  ): Promise<StoreGrant | null> {
    const current = await this.apple.current(originalTransactionId);
    return current
      ? grantFromAppStore(
          current.transaction,
          current.status,
          current.autoRenew,
        )
      : null;
  }
}
