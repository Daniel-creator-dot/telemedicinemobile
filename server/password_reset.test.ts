import assert from 'assert';
import {
  RESET_INVALID_MESSAGE,
  RESET_MIN_PASSWORD,
  normalizeResetCode,
  resetPasswordError,
  resetSmsText,
} from './password_reset';

assert.equal(resetSmsText('482913'), 'Healynks: your reset code is 482913. It expires in 10 minutes.');
assert.equal(resetPasswordError('short'), 'Use at least 8 characters.');
assert.equal(resetPasswordError('a'.repeat(RESET_MIN_PASSWORD - 1)), 'Use at least 8 characters.');
assert.equal(resetPasswordError('longenough'), null);
assert.equal(normalizeResetCode(' 482 913 '), '482913');
assert.equal(RESET_INVALID_MESSAGE, 'That code is not valid, or it has expired.');

console.log('password reset checks ok');
