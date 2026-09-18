import { registerAs } from '@nestjs/config';
import { IsEnum, IsOptional, IsString } from 'class-validator';
import validateConfig from '../utils/validate-config';

/**
 * How checkout behaves.
 *
 * `stub` takes no money and talks to nobody. It exists so the whole purchase path — order row,
 * activation, entitlement refresh — can be exercised before Cashfree credentials are issued, and it
 * is refused outright when `NODE_ENV=production`: a mode that pretends a payment succeeded must not
 * be one deploy away from doing so for real.
 */
export enum CashfreeMode {
  Stub = 'stub',
  Sandbox = 'sandbox',
  Production = 'production',
}

export type CashfreeConfig = {
  mode: CashfreeMode;
  appId: string | null;
  /**
   * The merchant's Client Secret, and the ONLY secret Cashfree uses.
   *
   * It authenticates API calls and it is also the HMAC key that signs webhooks — Cashfree has no
   * separate webhook secret to create, unlike Stripe or Razorpay. This code had a second variable
   * for one until the docs were read (D-198); a build configured with correct credentials would
   * have refused every webhook.
   */
  secretKey: string | null;
  returnUrl: string | null;
};

const API_BASE: Record<CashfreeMode, string> = {
  [CashfreeMode.Stub]: '',
  [CashfreeMode.Sandbox]: 'https://sandbox.cashfree.com/pg',
  [CashfreeMode.Production]: 'https://api.cashfree.com/pg',
};

export function cashfreeApiBase(mode: CashfreeMode): string {
  return API_BASE[mode];
}

class CashfreeEnvValidator {
  @IsEnum(CashfreeMode)
  @IsOptional()
  CASHFREE_MODE: CashfreeMode;

  /// Cashfree's own dashboard calls this the environment, so people write that name. Accepted as
  /// the same setting rather than silently ignored — a variable that looks like it switched on
  /// live payments and did not is the worst kind of config bug.
  @IsEnum(CashfreeMode)
  @IsOptional()
  CASHFREE_ENVIRONMENT: CashfreeMode;

  @IsString()
  @IsOptional()
  CASHFREE_APP_ID: string;

  @IsString()
  @IsOptional()
  CASHFREE_SECRET_KEY: string;

  @IsString()
  @IsOptional()
  CASHFREE_RETURN_URL: string;
}

/**
 * One setting under two names.
 *
 * Refuses when both are set and they disagree. Whether this build charges a real card must never
 * be decided by a precedence rule nobody remembers reading — the two lines in the file would say
 * different things and only one of them would be true.
 */
export function resolveMode(env: NodeJS.ProcessEnv): CashfreeMode {
  const mode = env.CASHFREE_MODE as CashfreeMode | undefined;
  const environment = env.CASHFREE_ENVIRONMENT as CashfreeMode | undefined;

  if (mode && environment && mode !== environment) {
    throw new Error(
      `CASHFREE_MODE=${mode} and CASHFREE_ENVIRONMENT=${environment} disagree. ` +
        'They are the same setting — keep one line and delete the other.',
    );
  }

  // Stub by default. A missing variable should leave a developer unable to take money, never
  // quietly pointing a half-configured build at the live gateway.
  return mode ?? environment ?? CashfreeMode.Stub;
}

export default registerAs<CashfreeConfig>('cashfree', () => {
  validateConfig(process.env, CashfreeEnvValidator);

  return {
    mode: resolveMode(process.env),
    appId: process.env.CASHFREE_APP_ID ?? null,
    secretKey: process.env.CASHFREE_SECRET_KEY ?? null,
    returnUrl: process.env.CASHFREE_RETURN_URL ?? null,
  };
});
