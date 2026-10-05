/**
 * Stubbed check for the home-care nurse alert.
 * Does not import sendSMS, does not read settings, and does not text anyone.
 */
import assert from 'assert';
import {
  homeCareAlertText,
  homeCareJobUrl,
  isApprovedHomeCareNurse,
  isHomeCareShareToken,
  newHomeCareShareToken,
  notifyApprovedNursesOfHomeCare,
  type HomeCareNurseCandidate,
} from './homecare_notify';

const token = 'aB3xY9kLm2Qp7Vw8Zn4Ht6';
const title = 'Wound dressing';
const location = 'East Legon';
const expected = `Healynks home care: ${title} in ${location}. Open https://healynks.app/homecare/${token}`;

assert.equal(homeCareAlertText(title, location, token), expected);
assert.equal(homeCareJobUrl(token), `https://healynks.app/homecare/${token}`);
assert.equal(expected.includes('/homecare/4'), false);
assert.equal(/\/homecare\/\d+$/.test(expected), false);
assert.equal(isHomeCareShareToken('42'), false);
assert.equal(isHomeCareShareToken('1234567890123456'), false);
assert.equal(isHomeCareShareToken(token), true);
assert.equal(isHomeCareShareToken(newHomeCareShareToken()), true);

const nurses: HomeCareNurseCandidate[] = [
  { id: 1, role: 'nurse', phone: '0241111111', verification_status: 'approved', is_active: true },
  { id: 2, role: 'nurse', phone: '0242222222', verification_status: 'approved', is_active: false },
  { id: 3, role: 'nurse', phone: '0243333333', verification_status: 'approved', is_active: null },
  { id: 4, role: 'nurse', phone: '0244444444', verification_status: 'pending', is_active: true },
  { id: 5, role: 'nurse', phone: '0245555555', verification_status: 'rejected', is_active: false },
  { id: 6, role: 'doctor', phone: '0246666666', verification_status: 'approved', is_active: true },
  { id: 7, role: 'patient', phone: '0247777777', verification_status: 'approved', is_active: true },
  { id: 8, role: 'nurse', phone: '', verification_status: null, is_active: true },
  { id: 8, role: 'nurse', phone: '0248888888', verification_status: null, is_active: true },
  { id: 9, role: 'nurse', phone: '0550000000', verification_status: 'Approved', is_active: true },
];

assert.equal(isApprovedHomeCareNurse(nurses[0]), true);
assert.equal(isApprovedHomeCareNurse(nurses[3]), false);
assert.equal(isApprovedHomeCareNurse(nurses[4]), false);
assert.equal(isApprovedHomeCareNurse(nurses[5]), false);
assert.equal(isApprovedHomeCareNurse(nurses[6]), false);
assert.equal(isApprovedHomeCareNurse({ id: 10, role: 'nurse', verification_status: '', is_active: false }), false);

async function main() {
const sms: string[] = [];
const inApp: number[] = [];
const pushed: number[] = [];

const summary = await notifyApprovedNursesOfHomeCare({
  nurses,
  title,
  location,
  token,
  writeNotification: async (userId, heading, message) => {
    if (userId === 1) throw new Error('notification row failed');
    assert.equal(heading, 'Healynks home care');
    assert.equal(message, expected);
    inApp.push(userId);
  },
  sendSMS: async (phone, message) => {
    assert.equal(message, expected);
    assert.equal(phone === '0247904675', false);
    if (phone === '0242222222') throw new Error('gateway down');
    sms.push(phone);
  },
  sendPush: async (userIds, heading, message, data) => {
    assert.equal(heading, 'Healynks home care');
    assert.equal(message, expected);
    assert.equal(data?.url, homeCareJobUrl(token));
    pushed.push(userIds[0]);
  },
});

assert.deepEqual(inApp, [2, 3, 8, 9]);
assert.deepEqual(sms, ['0241111111', '0243333333', '0550000000']);
assert.deepEqual(pushed, [1, 2, 3, 8, 9]);
assert.equal(summary.inApp, 4);
assert.equal(summary.sms, 3);
assert.equal(summary.skippedNoPhone, 1);
assert.equal(sms.includes('0244444444'), false);
assert.equal(sms.includes('0245555555'), false);
assert.equal(sms.includes('0246666666'), false);
assert.equal(sms.includes('0247777777'), false);

let rejected = false;
try {
  await notifyApprovedNursesOfHomeCare({
    nurses: [{ id: 1, role: 'nurse', phone: '0241111111', verification_status: 'approved' }],
    title,
    location,
    token: '15',
    sendSMS: async () => {
      throw new Error('must not send');
    },
    writeNotification: async () => {
      throw new Error('must not write');
    },
  });
} catch {
  rejected = true;
}
assert.equal(rejected, true);

console.log('homecare notify checks passed');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
