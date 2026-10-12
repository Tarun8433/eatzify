import ms from 'ms';

export type AuthConfig = {
  secret?: string;
  expires?: ms.StringValue;
  refreshSecret?: string;
  refreshExpires?: ms.StringValue;
  forgotSecret?: string;
  forgotExpires?: ms.StringValue;
  confirmEmailSecret?: string;
  confirmEmailExpires?: ms.StringValue;
  uniformErrors: boolean;
  /// OAuth Web client id; Google sign-in is refused while unset.
  googleWebClientId?: string;
};
