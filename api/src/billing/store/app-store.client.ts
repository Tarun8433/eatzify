import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from '@apple/app-store-server-library';
import type { AllConfigType } from '../../config/config.type';

/// Apple's current word on one subscription: its latest transaction, status and renewal intent.
export type AppStoreCurrent = {
  transaction: JWSTransactionDecodedPayload;
  status: number | undefined;
  autoRenew: boolean;
};

/// The App Store Server API and Apple's signature checks, and nothing else (payments plan,
/// Phase 5). Every decision about what a purchase means is in `store-rules.ts`.
@Injectable()
export class AppStoreClient {
  private api: AppStoreServerAPIClient | null = null;
  private verifier: SignedDataVerifier | null = null;

  constructor(private readonly config: ConfigService<AllConfigType>) {}

  get configured(): boolean {
    const c = (k: keyof AllConfigType['store']) =>
      !!this.config.get(`store.${k}`, { infer: true });
    return (
      c('appStoreIssuerId') &&
      c('appStoreKeyId') &&
      c('appStorePrivateKeyFile') &&
      c('appStoreRootCertsDir')
    );
  }

  /// Checks a StoreKit 2 signed transaction against Apple's root certificates and this app's
  /// bundle id. Throws `VerificationException` on anything forged, foreign or malformed.
  verifyTransaction(jws: string): Promise<JWSTransactionDecodedPayload> {
    return this.signed().verifyAndDecodeTransaction(jws);
  }

  verifyNotification(payload: string): Promise<ResponseBodyV2DecodedPayload> {
    return this.signed().verifyAndDecodeNotification(payload);
  }

  /// Re-reads the subscription from Apple — the signed transaction the phone sent says what was
  /// bought, not whether it is still paid for.
  async current(
    originalTransactionId: string,
  ): Promise<AppStoreCurrent | null> {
    const res = await this.client().getAllSubscriptionStatuses(
      originalTransactionId,
    );
    const item = (res.data ?? [])
      .flatMap((g) => g.lastTransactions ?? [])
      .find((t) => t.originalTransactionId === originalTransactionId);
    if (!item?.signedTransactionInfo) return null;

    const transaction = await this.verifyTransaction(
      item.signedTransactionInfo,
    );
    const renewal = item.signedRenewalInfo
      ? await this.signed().verifyAndDecodeRenewalInfo(item.signedRenewalInfo)
      : null;
    return {
      transaction,
      status: item.status,
      // AutoRenewStatus.ON is 1.
      autoRenew: renewal?.autoRenewStatus === 1,
    };
  }

  private environment(): Environment {
    return this.config.get('store.appStoreEnvironment', { infer: true }) ===
      'Production'
      ? Environment.PRODUCTION
      : Environment.SANDBOX;
  }

  private bundleId(): string {
    return this.required('appStoreBundleId');
  }

  private signed(): SignedDataVerifier {
    if (this.verifier) return this.verifier;
    const dir = this.required('appStoreRootCertsDir');
    const roots = readdirSync(dir)
      .filter((f) => /\.(cer|der)$/i.test(f))
      .map((f) => readFileSync(join(dir, f)));
    this.verifier = new SignedDataVerifier(
      roots,
      // Online revocation checks (OCSP) on the certificate chain.
      true,
      this.environment(),
      this.bundleId(),
      this.config.get('store.appStoreAppAppleId', { infer: true }) ?? undefined,
    );
    return this.verifier;
  }

  private client(): AppStoreServerAPIClient {
    if (this.api) return this.api;
    const keyFile = this.required('appStorePrivateKeyFile');
    this.api = new AppStoreServerAPIClient(
      readFileSync(keyFile, 'utf8'),
      this.required('appStoreKeyId'),
      this.required('appStoreIssuerId'),
      this.bundleId(),
      this.environment(),
    );
    return this.api;
  }

  private required(
    key:
      | 'appStoreBundleId'
      | 'appStoreIssuerId'
      | 'appStoreKeyId'
      | 'appStorePrivateKeyFile'
      | 'appStoreRootCertsDir',
  ): string {
    const value = this.config.get(`store.${key}`, { infer: true });
    if (!value) throw new Error(`store.${key} is not set`);
    return value;
  }
}
