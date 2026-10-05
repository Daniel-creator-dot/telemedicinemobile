/**
 * Intek request and response checks. Does not read settings and does not text anyone.
 */
/// <reference types="node" />
import assert from 'assert';
import { canonicalMsisdn, intekDeliveryResult, intekSendPayload, smsSendUrl } from './sms_gateway';

assert.equal(canonicalMsisdn('0241111111'), '233241111111');
assert.equal(canonicalMsisdn('+233241111111'), '233241111111');
assert.equal(canonicalMsisdn('2330241111111'), '233241111111');

assert.equal(smsSendUrl('https://www.inteksms.top/api/v1'), 'https://www.inteksms.top/api/v1/messages/send');
assert.equal(
  smsSendUrl('https://www.inteksms.top/api/v1/messages/send'),
  'https://www.inteksms.top/api/v1/messages/send'
);
assert.equal(
  smsSendUrl('https://www.inteksms.top/api/v1/messages/send/'),
  'https://www.inteksms.top/api/v1/messages/send'
);

const named = intekSendPayload('bytzee', '233241111111', 'Healynks home care: visit');
assert.equal(named.sender, 'bytzee');
assert.equal(named.sender_id, undefined);
assert.deepEqual(named.recipients, ['233241111111']);
assert.equal(Array.isArray(named.recipients), true);

const numeric = intekSendPayload('170', '233241111111', 'Healynks home care: visit');
assert.equal(numeric.sender, undefined);
assert.equal(numeric.sender_id, 170);
assert.deepEqual(numeric.recipients, ['233241111111']);

const accepted = intekDeliveryResult(200, {
  ok: true,
  data: { status: 'sent', recipients: 1 },
});
assert.equal(accepted.accepted, true);
assert.equal(accepted.status, 'sent');

const statusOnly = intekDeliveryResult(200, { status: 'sent' });
assert.equal(statusOnly.accepted, true);
assert.equal(statusOnly.status, 'sent');

const rejected = intekDeliveryResult(422, { ok: false, error: 'No valid recipients found' });
assert.equal(rejected.accepted, false);
assert.equal(rejected.status, 'failed');

const httpOkButFailed = intekDeliveryResult(200, { ok: true, data: { status: 'failed', recipients: 1 } });
assert.equal(httpOkButFailed.accepted, false);
assert.equal(httpOkButFailed.status, 'failed');

const emptyBody = intekDeliveryResult(200, {});
assert.equal(emptyBody.accepted, false);
assert.equal(emptyBody.status, 'failed');

const html = intekDeliveryResult(200, '<html>ok</html>');
assert.equal(html.accepted, false);
assert.equal(html.status, 'failed');

const zero = intekDeliveryResult(200, { ok: true, data: { status: 'sent', recipients: 0 } });
assert.equal(zero.accepted, false);

assert.equal(JSON.stringify(named).includes('api_key'), false);
assert.equal(accepted.status.includes('Bearer'), false);

console.log('sms gateway checks passed');
