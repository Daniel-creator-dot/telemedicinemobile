import axios from 'axios';
import { query } from './db';
import { canonicalMsisdn, intekDeliveryResult, intekSendPayload, smsSendUrl } from './sms_gateway';

export { canonicalMsisdn };

async function writeSmsLog(recipient: string, message: string, status: string): Promise<void> {
  const logged = String(status || 'failed').slice(0, 20);
  try {
    await query('INSERT INTO sms_logs (recipient, message, status) VALUES ($1, $2, $3)', [
      recipient.slice(0, 20),
      message,
      logged,
    ]);
  } catch (err) {
    console.error('Error writing sms_logs:', err);
  }
}

async function loadSmsSettings(): Promise<{ sms_base_url: string; sms_sender_id: string; sms_api_key: string }> {
  const settingsResult = await query('SELECT key, value FROM settings WHERE key = ANY($1::text[])', [
    ['sms_base_url', 'sms_sender_id', 'sms_api_key'],
  ]);
  const settings: Record<string, string> = {};
  for (const row of settingsResult.rows) settings[row.key] = row.value;
  return {
    sms_base_url: String(settings.sms_base_url || ''),
    sms_sender_id: String(settings.sms_sender_id || ''),
    sms_api_key: String(settings.sms_api_key || ''),
  };
}

/**
 * Send one SMS through the gateway stored in settings.
 * Reloads settings on every call. Returns false when the phone, the base URL,
 * or the provider response means the text was not accepted. Never throws.
 */
export async function deliverSMS(recipient: string | null | undefined, message: string): Promise<boolean> {
  const raw = String(recipient || '').trim();
  if (!raw) return false;

  let sent = false;
  try {
    const { sms_base_url, sms_sender_id, sms_api_key } = await loadSmsSettings();
    if (!sms_base_url.trim()) {
      console.warn('SMS Base URL not configured. Skipping SMS.');
      await writeSmsLog(raw, message, 'failed');
      return false;
    }

    const formattedRecipient = canonicalMsisdn(raw);
    if (!formattedRecipient) {
      await writeSmsLog(raw, message, 'failed');
      return false;
    }

    const sendUrl = smsSendUrl(sms_base_url);
    const payload = intekSendPayload(sms_sender_id, formattedRecipient, message);

    console.log(`[SMS SEND] Attempting to send to ${formattedRecipient} via ${sendUrl}`);

    let status = 'failed';
    try {
      const res = await axios.post(sendUrl, payload, {
        headers: {
          Authorization: `Bearer ${sms_api_key}`,
          'Content-Type': 'application/json',
        },
        timeout: 20000,
        validateStatus: () => true,
      });
      const outcome = intekDeliveryResult(res.status, res.data);
      sent = outcome.accepted;
      status = outcome.status;
      const body = res.data && typeof res.data === 'object' ? res.data : {};
      const summary = {
        http: res.status,
        ok: body.ok ?? null,
        provider: outcome.status,
        error: typeof body.error === 'string' ? body.error.slice(0, 180) : null,
      };
      console.log(sent ? '[SMS SUCCESS]' : '[SMS ERROR]', summary);
    } catch (err) {
      const detail = err instanceof Error ? err.message : 'request failed';
      console.error('[SMS ERROR]', detail);
      status = 'failed';
      sent = false;
    }

    await writeSmsLog(raw, message, status);
  } catch (err) {
    console.error('Error in sendSMS utility:', err);
    sent = false;
    await writeSmsLog(raw, message, 'failed');
  }
  return sent;
}

/** Same send as {@link deliverSMS}. Callers that only need a best-effort text use this. */
export async function sendSMS(recipient: string | null | undefined, message: string): Promise<void> {
  await deliverSMS(recipient, message);
}

export async function phoneForUser(userId: number | null | undefined): Promise<string | null> {
  if (!userId) return null;
  const result = await query(
    `SELECT phone FROM (
       SELECT NULLIF(BTRIM(phone_number), '') AS phone FROM users WHERE id = $1
       UNION ALL
       SELECT NULLIF(BTRIM(phone_number), '') FROM patients WHERE user_id = $1
     ) phones
     WHERE phone IS NOT NULL
     LIMIT 1`,
    [userId]
  );
  const phone = String(result.rows[0]?.phone || '').trim();
  return phone || null;
}

export function notificationSms(title: string, message: string): string {
  const body = String(message || '').trim();
  const head = String(title || '').trim();
  if (body.startsWith('Healynks:')) return body;
  if (head && body.toLowerCase().startsWith(head.toLowerCase())) return `Healynks: ${body}`;
  if (head && body) return `Healynks: ${head}. ${body}`;
  return `Healynks: ${head || body}`;
}

/** Text the user behind an in-app notification when a phone is on file. */
export async function smsUser(
  userId: number | null | undefined,
  title: string,
  message: string
): Promise<void> {
  const phone = await phoneForUser(userId);
  if (!phone) return;
  await sendSMS(phone, notificationSms(title, message));
}
