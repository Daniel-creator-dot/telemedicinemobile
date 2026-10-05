import { randomBytes } from 'crypto';

/** Public job link. The path segment is the share token, never the numeric id. */
export const HOME_CARE_LINK_ORIGIN = 'https://healynks.app';

const SHARE_TOKEN = /^[A-Za-z0-9_-]{16,128}$/;

export type HomeCareNurseCandidate = {
  id: number;
  role?: string | null;
  phone?: string | null;
  verification_status?: string | null;
  /** True when approval is stored on the nurses row instead of verification_status. */
  is_active?: boolean | null;
};

export type HomeCareSmsSender = (phone: string, message: string) => Promise<void>;

export type HomeCareNotificationWriter = (
  userId: number,
  title: string,
  message: string
) => Promise<void>;

export type HomeCarePushSender = (
  userIds: number[],
  title: string,
  body: string,
  data?: Record<string, string>
) => Promise<void>;

/** URL-safe and unguessable. Rejected if it is only digits so a raw id cannot be used. */
export function newHomeCareShareToken(): string {
  return randomBytes(18).toString('base64url');
}

export function isHomeCareShareToken(value: unknown): boolean {
  const token = String(value ?? '').trim();
  if (!SHARE_TOKEN.test(token)) return false;
  if (/^\d+$/.test(token)) return false;
  return true;
}

export function homeCareJobUrl(token: string): string {
  return `${HOME_CARE_LINK_ORIGIN}/homecare/${String(token).trim()}`;
}

function oneLine(value: string): string {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

/**
 * Plain SMS and in-app body.
 * "Healynks home care: {title} in {location}. Open {url}"
 */
export function homeCareAlertText(title: string, location: string, token: string): string {
  const job = oneLine(title);
  const place = oneLine(location);
  return `Healynks home care: ${job} in ${place}. Open ${homeCareJobUrl(token)}`;
}

/**
 * Approved nurses only.
 * Pending and rejected accounts are out, even when a nurse row was created with is_active true.
 * Agency owners are included when their user role is nurse and they are approved.
 */
export function isApprovedHomeCareNurse(row: HomeCareNurseCandidate): boolean {
  if (String(row.role || '').trim().toLowerCase() !== 'nurse') return false;
  const status = String(row.verification_status || '').trim().toLowerCase();
  if (status === 'pending' || status === 'rejected') return false;
  if (status === 'approved') return true;
  return row.is_active === true;
}

export type HomeCareAlertResult = {
  sms: number;
  inApp: number;
  skippedNoPhone: number;
};

/**
 * One in-app row and, when a phone is on the nurse account, one SMS.
 * A failure for one nurse does not stop the rest. Sequential on purpose.
 * Never reads the request contact phone; callers pass nurse accounts only.
 */
export async function notifyApprovedNursesOfHomeCare(input: {
  nurses: HomeCareNurseCandidate[];
  title: string;
  location: string;
  token: string;
  sendSMS: HomeCareSmsSender;
  writeNotification: HomeCareNotificationWriter;
  sendPush?: HomeCarePushSender;
}): Promise<HomeCareAlertResult> {
  if (!isHomeCareShareToken(input.token)) {
    throw new Error('home care alert requires an unguessable share token');
  }
  const message = homeCareAlertText(input.title, input.location, input.token);
  const url = homeCareJobUrl(input.token);
  const seen = new Set<number>();
  const result: HomeCareAlertResult = { sms: 0, inApp: 0, skippedNoPhone: 0 };

  for (const nurse of input.nurses) {
    if (!isApprovedHomeCareNurse(nurse)) continue;
    const userId = Number(nurse.id);
    if (!Number.isFinite(userId) || userId <= 0 || seen.has(userId)) continue;
    seen.add(userId);

    try {
      await input.writeNotification(userId, 'Healynks home care', message);
      result.inApp += 1;
    } catch (err) {
      console.error('home care in-app notification failed', userId, err instanceof Error ? err.message : 'error');
    }

    if (input.sendPush) {
      try {
        await input.sendPush([userId], 'Healynks home care', message, { type: 'homecare', url });
      } catch (err) {
        console.error('home care push failed', userId, err instanceof Error ? err.message : 'error');
      }
    }

    const phone = String(nurse.phone || '').trim();
    if (!phone) {
      result.skippedNoPhone += 1;
      console.log(`[HOME CARE] Skipping SMS, no phone on file for user ${userId}`);
      continue;
    }

    try {
      await input.sendSMS(phone, message);
      result.sms += 1;
    } catch (err) {
      console.error('home care sms failed', userId, err instanceof Error ? err.message : 'error');
    }
  }

  return result;
}
