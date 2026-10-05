/** Copy and checks for the login-screen password reset. */

export const RESET_CODE_TTL = '10 minutes';

export const RESET_GENERIC_MESSAGE =
  'If an account matches, a reset code is on its way by text.';

export const RESET_INVALID_MESSAGE = 'That code is not valid, or it has expired.';

export const RESET_SMS_FAILED_MESSAGE = 'We could not send the text. Try again in a moment.';

export const RESET_SHORT_PASSWORD_MESSAGE = 'Use at least 8 characters.';

export const RESET_MIN_PASSWORD = 8;

export function resetSmsText(code: string): string {
  return `Healynks: your reset code is ${code}. It expires in 10 minutes.`;
}

export function resetPasswordError(password: unknown): string | null {
  const value = String(password ?? '');
  if (value.length < RESET_MIN_PASSWORD) return RESET_SHORT_PASSWORD_MESSAGE;
  return null;
}

/** Digits only, so a code pasted with spaces still matches the text. */
export function normalizeResetCode(raw: unknown): string {
  return String(raw ?? '').replace(/\D/g, '');
}
