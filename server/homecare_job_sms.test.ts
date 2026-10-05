/**
 * Create and reshare each call the sender once per approved nurse.
 * A pending nurse is not texted. A rejected gateway response does not skip the rest.
 * Does not import the database and does not text anyone.
 */
/// <reference types="node" />
import assert from 'assert';
import {
  homeCareAlertText,
  homeCareCandidateFromRow,
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

const pendingOnNurseRow = homeCareCandidateFromRow({
  id: 4,
  role: 'Nurse',
  phone: '0244444444',
  user_status: null,
  nurse_status: 'pending',
  is_active: true,
});
assert.equal(isApprovedHomeCareNurse(pendingOnNurseRow), false);

const approvedAgency = homeCareCandidateFromRow({
  id: 11,
  role: 'nurse',
  phone: '0203332211',
  user_status: 'approved',
  nurse_status: null,
  is_active: null,
});
assert.equal(isApprovedHomeCareNurse(approvedAgency), true);

const blankActive = homeCareCandidateFromRow({
  id: 12,
  role: 'nurse',
  phone: '0501112233',
  user_status: '',
  nurse_status: '',
  is_active: 't',
});
assert.equal(isApprovedHomeCareNurse(blankActive), true);

const nurses: HomeCareNurseCandidate[] = [
  { id: 1, role: 'nurse', phone: '0241111111', verification_status: 'approved', is_active: true },
  { id: 2, role: 'nurse', phone: '0242222222', verification_status: 'approved', is_active: false },
  pendingOnNurseRow,
  { id: 5, role: 'nurse', phone: blockedPhone, verification_status: 'rejected', is_active: true },
  { id: 6, role: 'doctor', phone: '0246666666', verification_status: 'approved', is_active: true },
  approvedAgency,
  blankActive,
  { id: 13, role: 'nurse', phone: '', verification_status: 'approved', is_active: true },
];

async function countSends(run: typeof notifyApprovedNursesOfHomeCare) {
  const sms: string[] = [];
  await run({
    nurses,
    title,
    location,
    token,
    writeNotification: async () => undefined,
    sendSMS: async (phone, message) => {
      assert.equal(message, expected);
      assert.equal(phone === blockedPhone, false);
      assert.equal(phone === '0244444444', false);
      if (phone === '0242222222') return false;
      sms.push(phone);
      return true;
    },
  });
  return sms;
}

async function main() {
  const created = await countSends(notifyApprovedNursesOfHomeCare);
  assert.deepEqual(created, ['0241111111', '0203332211', '0501112233']);

  const reshared = await countSends(reshareHomeCareToNurses);
  assert.deepEqual(reshared, ['0241111111', '0203332211', '0501112233']);

  const approvedWithPhone = nurses.filter(
    (row) => isApprovedHomeCareNurse(row) && String(row.phone || '').trim() && row.id !== 2
  );
  assert.equal(created.length, approvedWithPhone.length);
  assert.equal(reshared.length, approvedWithPhone.length);
  assert.equal(created.includes('0244444444'), false);
  assert.equal(created.includes(blockedPhone), false);

  console.log('homecare job sms checks passed');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
