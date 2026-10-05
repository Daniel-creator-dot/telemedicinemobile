/**
 * Stubbed check for resharing a home-care job.
 * Does not import sendSMS, does not read settings, and does not text anyone.
 */
import assert from 'assert';
import {
  homeCareAlertText,
  isApprovedHomeCareNurse,
  notifyApprovedNursesOfHomeCare,
  reshareHomeCareToNurses,
  type HomeCareNurseCandidate,
} from './homecare_notify';

const token = 'aB3xY9kLm2Qp7Vw8Zn4Ht6';
const title = 'Wound dressing';
const location = 'East Legon';
const expected = homeCareAlertText(title, location, token);
const blockedPhone = '0247904675';

const nurses: HomeCareNurseCandidate[] = [
  { id: 1, role: 'nurse', phone: '0241111111', verification_status: 'approved', is_active: true },
  { id: 2, role: 'nurse', phone: '0242222222', verification_status: 'approved', is_active: false },
  { id: 3, role: 'nurse', phone: '', verification_status: 'approved', is_active: true },
  { id: 4, role: 'nurse', phone: '0244444444', verification_status: 'pending', is_active: true },
  { id: 5, role: 'nurse', phone: blockedPhone, verification_status: 'rejected', is_active: true },
  { id: 6, role: 'doctor', phone: '0246666666', verification_status: 'approved', is_active: true },
  { id: 7, role: 'patient', phone: blockedPhone, verification_status: 'approved', is_active: true },
  { id: 8, role: 'admin', phone: '0248888888', verification_status: 'approved', is_active: true },
  { id: 9, role: 'nurse', phone: '0550000000', verification_status: 'Approved', is_active: true },
  { id: 9, role: 'nurse', phone: '0550000000', verification_status: 'approved', is_active: true },
  { id: 10, role: 'nurse', phone: '0201231234', verification_status: null, is_active: true },
];

async function main() {
  const approved = new Set(
    nurses.filter((row) => isApprovedHomeCareNurse(row)).map((row) => row.id)
  );
  assert.deepEqual([...approved].sort((a, b) => a - b), [1, 2, 3, 9, 10]);

  const sms: string[] = [];
  const inApp: number[] = [];
  let notifierCalls = 0;

  const summary = await reshareHomeCareToNurses(
    {
      nurses,
      title,
      location,
      token,
      writeNotification: async () => {
        throw new Error('the reshare function must go through the notifier');
      },
      sendSMS: async () => {
        throw new Error('the reshare function must go through the notifier');
      },
    },
    async (input) => {
      notifierCalls += 1;
      assert.equal(input.nurses.length, 1);
      assert.equal(isApprovedHomeCareNurse(input.nurses[0]), true);
      assert.equal(input.nurses.some((row) => String(row.phone || '') === blockedPhone), false);
      return notifyApprovedNursesOfHomeCare({
        ...input,
        writeNotification: async (userId, heading, message) => {
          assert.equal(heading, 'Healynks home care');
          assert.equal(message, expected);
          inApp.push(userId);
        },
        sendSMS: async (phone, message) => {
          assert.equal(message, expected);
          assert.equal(phone === blockedPhone, false);
          sms.push(phone);
        },
      });
    }
  );

  assert.equal(notifierCalls, approved.size);
  assert.deepEqual(inApp, [1, 2, 3, 9, 10]);
  assert.deepEqual(sms, ['0241111111', '0242222222', '0550000000', '0201231234']);
  assert.equal(summary.inApp, 5);
  assert.equal(summary.sms, 4);
  assert.equal(summary.skippedNoPhone, 1);
  assert.equal(sms.includes(blockedPhone), false);
  assert.equal(sms.includes('0244444444'), false);
  assert.equal(inApp.includes(4), false);
  assert.equal(inApp.includes(5), false);
  assert.equal(inApp.includes(6), false);
  assert.equal(inApp.includes(7), false);
  assert.equal(inApp.includes(8), false);

  console.log('homecare reshare checks passed');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
