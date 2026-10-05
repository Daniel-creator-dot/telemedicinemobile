/**
 * Who took a home care job. No database and no SMS.
 */
import assert from 'assert';
import { homeCareClaimant, serialize, viewerMaySeeHomeCareClaimant } from './homecare';

const nurseRow = {
  id: 8,
  title: 'Wound dressing',
  status: 'claimed',
  location: 'Osu, Accra',
  contact_phone: '0244000000',
  note: 'Family is home',
  claimed_by: 3,
  claimed_name: 'Ama Boateng',
  claimed_phone: '0555111222',
  claimed_nurse_name: 'Ama Boateng',
  claimed_practice_area: 'General nursing',
  claimed_facility: 'Ridge Hospital',
  claimed_license_number: 'NMC-2048',
  claimed_agency_name: null,
  referrer_user_id: 7,
  password: 'should-never-leave-the-row',
  notes: 'private clinical note',
};

const agencyRow = {
  ...nurseRow,
  claimed_name: 'Kojo Mensah',
  claimed_phone: '',
  claimed_agency_phone: '0200888777',
  claimed_agency_name: 'Ridge Care Agency',
  claimed_agency_region: 'Greater Accra',
  claimed_agency_town: 'East Legon',
  claimed_practice_area: '   ',
  claimed_facility: null,
  claimed_license_number: null,
};

const nurseClaimant = homeCareClaimant(nurseRow);
assert.ok(nurseClaimant);
assert.equal(nurseClaimant.name, 'Ama Boateng');
assert.equal(nurseClaimant.phone, '0555111222');
assert.equal(nurseClaimant.kind, 'nurse');
assert.equal(nurseClaimant.practice_area, 'General nursing');
assert.equal(nurseClaimant.license_number, 'NMC-2048');
assert.equal(nurseClaimant.facility, 'Ridge Hospital');
assert.equal(nurseClaimant.agency_name, undefined);
assert.equal('password' in nurseClaimant, false);
assert.equal('id' in nurseClaimant, false);
assert.equal('user_id' in nurseClaimant, false);
assert.equal('notes' in nurseClaimant, false);

const agencyClaimant = homeCareClaimant(agencyRow);
assert.ok(agencyClaimant);
assert.equal(agencyClaimant.kind, 'agency');
assert.equal(agencyClaimant.name, 'Kojo Mensah');
assert.equal(agencyClaimant.phone, '0200888777');
assert.equal(agencyClaimant.agency_name, 'Ridge Care Agency');
assert.equal(agencyClaimant.region, 'Greater Accra');
assert.equal(agencyClaimant.town, 'East Legon');
assert.equal(agencyClaimant.practice_area, undefined);
assert.equal(agencyClaimant.facility, undefined);
assert.equal(agencyClaimant.license_number, undefined);

assert.equal(homeCareClaimant({ ...nurseRow, claimed_by: null }), null);
assert.equal(
  homeCareClaimant({ ...nurseRow, claimed_phone: '   ', claimed_agency_phone: null })?.phone,
  undefined
);

assert.equal(viewerMaySeeHomeCareClaimant({ id: 1, role: 'admin' }, nurseRow), true);
assert.equal(viewerMaySeeHomeCareClaimant({ id: 7, role: 'doctor' }, nurseRow), true);
assert.equal(viewerMaySeeHomeCareClaimant({ id: 9, role: 'doctor' }, nurseRow), false);
assert.equal(viewerMaySeeHomeCareClaimant({ id: 4, role: 'nurse' }, nurseRow), false);
assert.equal(viewerMaySeeHomeCareClaimant({ id: 3, role: 'nurse' }, nurseRow), false);

const adminView = serialize(nurseRow, { id: 1, role: 'admin' });
assert.equal((adminView.claimant as { phone?: string }).phone, '0555111222');
assert.equal((adminView.claimant as { kind?: string }).kind, 'nurse');

const referrerView = serialize(nurseRow, { id: 7, role: 'doctor' });
assert.equal((referrerView.claimant as { phone?: string }).phone, '0555111222');

const otherDoctor = serialize(nurseRow, { id: 9, role: 'doctor' });
assert.equal(otherDoctor.claimant, undefined);
assert.equal('claimant' in otherDoctor, false);

const otherNurse = serialize(nurseRow, { id: 4, role: 'nurse' });
assert.equal(otherNurse.claimant, undefined);
assert.equal(JSON.stringify(otherNurse).includes('0555111222'), false);
assert.equal(otherNurse.claimed_by_label, 'Ama Boateng');

const taker = serialize(nurseRow, { id: 3, role: 'nurse' });
assert.equal(taker.claimant, undefined);
assert.equal(JSON.stringify(taker).includes('0555111222'), false);

const open = serialize({ ...nurseRow, status: 'open', claimed_by: null }, { id: 1, role: 'admin' });
assert.equal(open.claimant, undefined);

console.log('homecare claimant checks passed');
