import assert from 'assert';
import {
  canStaffOnboard,
  canTextOnboardPhone,
  DUPLICATE_PHONE_MESSAGE,
  onboardFieldError,
  onboardSmsText,
  readableSignInPassword,
} from './patient_onboard';

assert.equal(onboardFieldError({}), "Enter the patient's full name.");
assert.equal(onboardFieldError({ full_name: 'Ama Mensah' }), "Enter the patient's mobile number.");
assert.equal(onboardFieldError({ full_name: 'Ama Mensah', phone: '0244000000' }), null);

assert.equal(canStaffOnboard('admin', null), true);
assert.equal(canStaffOnboard('doctor', 'pending'), true);
assert.equal(canStaffOnboard('nurse', 'approved'), true);
assert.equal(canStaffOnboard('nurse', 'Approved'), true);
assert.equal(canStaffOnboard('nurse', 'pending'), false);
assert.equal(canStaffOnboard('nurse', null), false);
assert.equal(canStaffOnboard('patient', 'approved'), false);
assert.equal(canStaffOnboard('medical_ops', 'approved'), false);

assert.equal(canTextOnboardPhone('0247904675'), false);
assert.equal(canTextOnboardPhone('+233247904675'), false);
assert.equal(canTextOnboardPhone('0244111222'), true);

const text = onboardSmsText('Ama');
assert.equal(
  text,
  'Healynks: Ama started your care record. Open https://healynks.app/login and sign in with this phone.'
);
assert.equal(text.includes('0247904675'), false);

const password = readableSignInPassword('River', 4821);
assert.equal(password, 'River4821');
assert.ok(password.length >= 8);

assert.equal(DUPLICATE_PHONE_MESSAGE, 'This phone already has a Healynks record.');

console.log('patient_onboard.test.ts ok');
