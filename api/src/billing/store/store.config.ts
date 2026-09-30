import { registerAs } from '@nestjs/config';
import { IsIn, IsNumberString, IsOptional, IsString } from 'class-validator';
import validateConfig from '../../utils/validate-config';

/// Payments plan, Phases 4–5: Google Play and App Store purchase verification. Everything optional — a server with
/// none of it set answers store calls with `STORE_NOT_CONFIGURED` instead of refusing to boot.
export type StoreConfig = {
  playPackageName: string;
  /// Path to the Google Cloud service-account JSON key with Play Developer API access. A path,
  /// never the key itself in an env var, and the file is never committed.
  playServiceAccountFile: string | null;
  /// Shared secret on the Pub/Sub push URL (`?token=`). A notification only makes the server
  /// re-read the purchase from Google, so this guards against noise, not forgery.
  playRtdnToken: string | null;
  /// Payments plan, Phase 5. The iOS bundle id every signed transaction must carry.
  appStoreBundleId: string;
  /// `Sandbox` or `Production` — which Apple servers are asked, and which signed data is accepted.
  appStoreEnvironment: 'Sandbox' | 'Production';
  /// App Store Connect API key (Users and Access → Integrations → In-App Purchase). A path to the
  /// .p8 file, never the key itself.
  appStoreIssuerId: string | null;
  appStoreKeyId: string | null;
  appStorePrivateKeyFile: string | null;
  /// Folder holding Apple's root certificates (`AppleRootCA-G3.cer` etc. from
  /// apple.com/certificateauthority). Signed transactions are checked against these.
  appStoreRootCertsDir: string | null;
  /// The app's numeric Apple ID. Required by Apple's verifier in Production.
  appStoreAppAppleId: number | null;
};

class StoreEnvValidator {
  @IsString()
  @IsOptional()
  GOOGLE_PLAY_PACKAGE_NAME: string;

  @IsString()
  @IsOptional()
  GOOGLE_PLAY_SERVICE_ACCOUNT_FILE: string;

  @IsString()
  @IsOptional()
  GOOGLE_PLAY_RTDN_TOKEN: string;

  @IsString()
  @IsOptional()
  APP_STORE_BUNDLE_ID: string;

  @IsIn(['Sandbox', 'Production'])
  @IsOptional()
  APP_STORE_ENVIRONMENT: string;

  @IsString()
  @IsOptional()
  APP_STORE_ISSUER_ID: string;

  @IsString()
  @IsOptional()
  APP_STORE_KEY_ID: string;

  @IsString()
  @IsOptional()
  APP_STORE_PRIVATE_KEY_FILE: string;

  @IsString()
  @IsOptional()
  APP_STORE_ROOT_CERTS_DIR: string;

  @IsNumberString()
  @IsOptional()
  APP_STORE_APP_APPLE_ID: string;
}

export default registerAs<StoreConfig>('store', () => {
  validateConfig(process.env, StoreEnvValidator);

  return {
    playPackageName:
      process.env.GOOGLE_PLAY_PACKAGE_NAME ?? 'com.zynthovo.eatzify',
    playServiceAccountFile:
      process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE || null,
    playRtdnToken: process.env.GOOGLE_PLAY_RTDN_TOKEN || null,
    appStoreBundleId: process.env.APP_STORE_BUNDLE_ID ?? 'app.eatzify',
    appStoreEnvironment:
      process.env.APP_STORE_ENVIRONMENT === 'Production'
        ? 'Production'
        : 'Sandbox',
    appStoreIssuerId: process.env.APP_STORE_ISSUER_ID || null,
    appStoreKeyId: process.env.APP_STORE_KEY_ID || null,
    appStorePrivateKeyFile: process.env.APP_STORE_PRIVATE_KEY_FILE || null,
    appStoreRootCertsDir: process.env.APP_STORE_ROOT_CERTS_DIR || null,
    appStoreAppAppleId: process.env.APP_STORE_APP_APPLE_ID
      ? Number(process.env.APP_STORE_APP_APPLE_ID)
      : null,
  };
});
