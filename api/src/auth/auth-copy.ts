/// What the app shows for each sign-in outcome (rule 7: the server owns user-facing error text).
/// Deliberately vague where precision would leak: login and forgot-password never say whether an
/// email has an account.
export const INVALID_CREDENTIALS = 'Email or password is incorrect.';
export const EMAIL_NOT_VERIFIED =
  'Please verify your email first. We have sent you a new code.';
export const EMAIL_TAKEN =
  'An account with this email already exists. Sign in instead.';
export const CODE_INVALID =
  'That code is not right. Check the email and try again.';
export const CODE_EXPIRED = 'That code has expired. Request a new one.';
export const CODE_LOCKED = 'Too many wrong tries. Request a new code.';
export const CODE_RATE_LIMITED =
  'Too many codes requested. Please try again in an hour.';
export const CODE_EMAIL_TITLE = 'Your Eatzify verification code';
export const codeEmailBody = (code: string): string =>
  `Your code is ${code}. It expires in 10 minutes.\n\nIf you did not try to sign up for Eatzify, you can ignore this email.`;
