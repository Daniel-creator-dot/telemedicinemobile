import axios from 'axios';
import { query } from './db';

/** Ghana local 024… becomes 23324…. Numbers that already include a country code are left as digits. */
export function canonicalMsisdn(raw: string): string {
  let digits = String(raw || '').replace(/[^0-9+]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (digits.startsWith('0')) digits = `233${digits.slice(1)}`;
  return digits;
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
      return false;
    }

    const formattedRecipient = canonicalMsisdn(raw);
    if (!formattedRecipient) return false;

    const base = sms_base_url.trim().replace(/\/+$/, '');
    const sendUrl = /\/messages\/send$/i.test(base) ? base : `${base}/messages/send`;

    console.log(`[SMS SEND] Attempting to send to ${formattedRecipient} via ${sendUrl}`);

    let status = 'failed';
    try {
      const res = await axios.post(
        sendUrl,
        {
          sender: sms_sender_id,
          recipients: [formattedRecipient],
          message,
        },
        {
          headers: {
            Authorization: `Bearer ${sms_api_key}`,
            'Content-Type': 'application/json',
          },
          timeout: 20000,
          validateStatus: () => true,
        }
      );
      const body = res.data && typeof res.data === 'object' ? res.data : {};
      const accepted = res.status >= 200 && res.status < 300 && body.ok !== false;
      sent = accepted;
      status = accepted ? 'sent' : 'failed';
      const summary = {
        http: res.status,
        ok: body.ok ?? null,
        error: typeof body.error === 'string' ? body.error : null,
      };
      console.log(accepted ? '[SMS SUCCESS]' : '[SMS ERROR]', summary);
    } catch (err) {
      const detail = err instanceof Error ? err.message : 'request failed';
      console.error('[SMS ERROR]', detail);
      status = 'failed';
      sent = false;
    }

    try {
      await query('INSERT INTO sms_logs (recipient, message, status) VALUES ($1, $2, $3)', [
        raw.slice(0, 20),
        message,
        status,
      ]);
    } catch (err) {
      console.error('Error writing sms_logs:', err);
    }
  } catch (err) {
    console.error('Error in sendSMS utility:', err);
    sent = false;
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
