/**
 * Intek SMS request and response shape.
 * Docs: POST {base}/messages/send with Bearer auth.
 * Body is { sender, recipients, message } for a sender name,
 * or { sender_id, recipients, message } when the setting is a numeric id.
 * A previous accepted send returned HTTP 200 and status "sent".
 * Recipients must be an array. A string is rejected as no valid recipients.
 */

const PROVIDER_OK = new Set(['sent', 'queued', 'accepted', 'delivered', 'success']);
const PROVIDER_BAD = new Set(['failed', 'rejected', 'error', 'undelivered', 'invalid']);

/** Ghana 024… becomes 23324…. A 2330… trunk prefix is folded to 233…. */
export function canonicalMsisdn(raw: string): string {
  let digits = String(raw || '').replace(/[^0-9+]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (digits.startsWith('0')) digits = `233${digits.slice(1)}`;
  if (digits.startsWith('2330') && digits.length === 13) digits = `233${digits.slice(4)}`;
  return digits;
}

/** Join the API root to /messages/send once. A base that already ends there is left alone. */
export function smsSendUrl(smsBaseUrl: string): string {
  const base = String(smsBaseUrl || '').trim().replace(/\/+$/, '');
  if (/\/messages\/send$/i.test(base)) return base;
  return `${base}/messages/send`;
}

/**
 * Intek accepts a sender name in `sender` or a numeric id in `sender_id`.
 * Recipients are always an array of one canonical number.
 */
export function intekSendPayload(
  senderSetting: string,
  recipientDigits: string,
  message: string
): { sender?: string; sender_id?: number; recipients: string[]; message: string } {
  const sender = String(senderSetting || '').trim();
  const body: { sender?: string; sender_id?: number; recipients: string[]; message: string } = {
    recipients: [recipientDigits],
    message,
  };
  if (/^\d+$/.test(sender)) body.sender_id = Number(sender);
  else body.sender = sender;
  return body;
}

function providerStatus(payload: unknown): string {
  if (!payload || typeof payload !== 'object') return '';
  const body = payload as { status?: unknown; data?: { status?: unknown } };
  const nested = body.data && typeof body.data === 'object' ? body.data.status : undefined;
  return String(nested ?? body.status ?? '').trim().toLowerCase();
}

/**
 * Accept only a 2xx body that Intek marks ok, or that carries a success status.
 * A bare HTTP 200 (HTML, empty object, or ok missing) is a failure.
 * status "failed" is a failure even when the HTTP status is 200.
 * The returned status is safe to store in sms_logs and never includes a key.
 */
export function intekDeliveryResult(
  httpStatus: number,
  payload: unknown
): { accepted: boolean; status: string } {
  const body = payload && typeof payload === 'object' ? (payload as { ok?: unknown; data?: { recipients?: unknown } }) : {};
  const nested = body.data && typeof body.data === 'object' ? body.data : {};
  const provider = providerStatus(payload);
  const httpOk = httpStatus >= 200 && httpStatus < 300;
  const noRecipients = typeof nested.recipients === 'number' && nested.recipients <= 0;
  const providerFailed = PROVIDER_BAD.has(provider);
  const providerOk = PROVIDER_OK.has(provider);
  const accepted =
    httpOk &&
    body.ok !== false &&
    !providerFailed &&
    !noRecipients &&
    (body.ok === true || providerOk);
  const logged = (accepted ? provider || 'sent' : provider && !PROVIDER_OK.has(provider) ? provider : 'failed').slice(0, 20);
  return { accepted, status: logged || (accepted ? 'sent' : 'failed') };
}
