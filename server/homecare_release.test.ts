/**
 * Who may release or reactivate a home care job.
 * No database and no SMS.
 */
import assert from 'assert';
import {
  homeCareReactivateDecision,
  homeCareReleaseAdminMessage,
  homeCareReleaseDecision,
} from './homecare';

const taken = { status: 'claimed', claimed_by: 3 };

assert.equal(homeCareReleaseDecision(3, taken), 'ok');
assert.equal(homeCareReleaseDecision(4, taken), 'forbidden');
assert.equal(homeCareReleaseDecision(7, taken), 'forbidden');
assert.equal(homeCareReleaseDecision(1, taken), 'forbidden');
assert.equal(homeCareReleaseDecision(3, { status: 'open', claimed_by: null }), 'not_claimed');
assert.equal(homeCareReleaseDecision(3, { status: 'closed', claimed_by: 3 }), 'not_claimed');
assert.equal(homeCareReleaseDecision(3, { status: 'claimed', claimed_by: null }), 'not_claimed');
assert.equal(homeCareReleaseDecision(3, null), 'not_found');

assert.equal(homeCareReactivateDecision('admin', { status: 'closed', claimed_by: 3 }), 'ok');
assert.equal(homeCareReactivateDecision('admin', taken), 'ok');
assert.equal(homeCareReactivateDecision('admin', { status: 'closed', claimed_by: null }), 'ok');
assert.equal(homeCareReactivateDecision('admin', { status: 'open', claimed_by: null }), 'already_open');
assert.equal(homeCareReactivateDecision('admin', { status: 'open', claimed_by: 3 }), 'ok');
assert.equal(homeCareReactivateDecision('doctor', { status: 'closed', claimed_by: 3 }), 'forbidden');
assert.equal(homeCareReactivateDecision('nurse', taken), 'forbidden');
assert.equal(homeCareReactivateDecision('admin', null), 'not_found');

const message = homeCareReleaseAdminMessage('Ama Boateng', 'Wound dressing');
assert.equal(message, 'Ama Boateng released the home care job Wound dressing.');
assert.equal(message.includes('024'), false);
assert.equal(message.toLowerCase().includes('sms'), false);
assert.equal(
  homeCareReleaseAdminMessage('  ', '  '),
  'A caregiver released the home care job Home care.'
);

console.log('homecare release checks passed');
