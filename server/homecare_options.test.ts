/**
 * Edit planning for home care. No database and no SMS.
 */
import assert from 'assert';
import {
  HOME_CARE_OPTION_LABELS,
  HOME_CARE_STAY_IN_LINE,
  homeCarePatchColumns,
  homeCareShowsStayIn,
  homeCareUpdateStatement,
  normalizeCustomOption,
  normalizeHomeCareOptions,
} from './homecare_options';

assert.deepEqual(
  normalizeHomeCareOptions(['overnight', 'Stay-in', 'Not a real option', 'stay-in', 'Wound care']),
  ['Stay-in', 'Overnight', 'Wound care']
);
assert.deepEqual(normalizeHomeCareOptions('Stay-in'), []);
assert.deepEqual(normalizeHomeCareOptions(null), []);
assert.equal(HOME_CARE_OPTION_LABELS.length, 7);
assert.equal(normalizeCustomOption('  feeding   help  '), 'feeding help');
assert.equal(normalizeCustomOption('   '), null);
assert.equal(normalizeCustomOption('x'.repeat(80))?.length, 48);
assert.equal(homeCareShowsStayIn(['Stay-in'], null), true);
assert.equal(homeCareShowsStayIn([], 'stay in'), true);
assert.equal(homeCareShowsStayIn(['Day visit'], 'feeding help'), false);
assert.equal(HOME_CARE_STAY_IN_LINE, 'The caregiver stays in the home.');

const openSql = homeCareUpdateStatement(true);
const takenSql = homeCareUpdateStatement(false);
assert.deepEqual(homeCarePatchColumns(true), [
  'title',
  'location',
  'contact_phone',
  'note',
  'care_options',
  'custom_option',
]);
assert.deepEqual(homeCarePatchColumns(false), ['contact_phone', 'note']);
assert.equal(openSql.includes('claimed_by ='), false);
assert.equal(openSql.includes('SET status'), false);
assert.equal(openSql.includes("status = 'open'"), true);
assert.equal(openSql.includes('claimed_by IS NULL'), true);
assert.equal(takenSql.toLowerCase().includes('claimed_by'), false);
assert.equal(takenSql.toLowerCase().includes('status'), false);
assert.equal(takenSql.toLowerCase().includes('title'), false);
assert.equal(takenSql.toLowerCase().includes('care_options'), false);
assert.equal(openSql.toLowerCase().includes('sms'), false);
assert.equal(takenSql.toLowerCase().includes('sms'), false);

console.log('homecare option checks passed');
