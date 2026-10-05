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

/** Resolves false when the gateway did not accept the text. A throw is also a failure. */
export type HomeCareSmsSender = (phone: string, message: string) => Promise<boolean | void>;

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
 * Role nurse, and either verification_status approved, or a blank status with nurses.is_active.
 * Pending and rejected stay out, even when is_active was set true at signup.
 * Agency owners are included when their user role is nurse and they are approved.
 */
function nurseFlag(value: unknown): boolean {
  return value === true || value === 't' || value === 'true';
}

/**
 * User review wins when it is set. A blank user status uses the nurses row.
 * That keeps a pending nurse row from looking approved just because is_active is true.
 */
export function homeCareCandidateFromRow(row: {
  id: unknown;
  role?: unknown;
  phone?: unknown;
  user_status?: unknown;
  nurse_status?: unknown;
  verification_status?: unknown;
  is_active?: unknown;
}): HomeCareNurseCandidate {
  const userStatus = String(row.user_status ?? row.verification_status ?? '').trim();
  const nurseStatus = String(row.nurse_status ?? '').trim();
  const status = userStatus || nurseStatus;
  const phone = String(row.phone ?? '').trim();
  return {
    id: Number(row.id),
    role: row.role == null ? null : String(row.role),
    phone: phone || null,
    verification_status: status || null,
    is_active: nurseFlag(row.is_active),
  };
}

export function isApprovedHomeCareNurse(row: HomeCareNurseCandidate): boolean {
  if (String(row.role || '').trim().toLowerCase() !== 'nurse') return false;
  const status = String(row.verification_status ?? '').trim().toLowerCase();
  if (status === 'approved') return true;
  if (status === 'pending' || status === 'rejected') return false;
  if (status !== '') return false;
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

    const phone = String(nurse.phone || '').trim();
    if (!phone) {
      result.skippedNoPhone += 1;
      console.log(`[HOME CARE] Skipping SMS, no phone on file for user ${userId}`);
    } else {
      try {
        const delivered = await input.sendSMS(phone, message);
        if (delivered === false) {
          console.error('home care sms rejected', userId);
        } else {
          result.sms += 1;
        }
      } catch (err) {
        console.error('home care sms failed', userId, err instanceof Error ? err.message : 'error');
      }
    }

    if (input.sendPush) {
      try {
        await input.sendPush([userId], 'Healynks home care', message, { type: 'homecare', url });
      } catch (err) {
        console.error('home care push failed', userId, err instanceof Error ? err.message : 'error');
      }
    }
  }

  return result;
}

/**
 * Sends the same home-care alert again.
 * Calls the notifier once for each approved nurse. That notifier owns the SMS
 * and in-app rules. Pending, rejected, and non-nurse accounts are not included.
 */
export async function reshareHomeCareToNurses(
  input: {
    nurses: HomeCareNurseCandidate[];
    title: string;
    location: string;
    token: string;
    sendSMS: HomeCareSmsSender;
    writeNotification: HomeCareNotificationWriter;
    sendPush?: HomeCarePushSender;
  },
  notify: typeof notifyApprovedNursesOfHomeCare = notifyApprovedNursesOfHomeCare
): Promise<HomeCareAlertResult> {
  const totals: HomeCareAlertResult = { sms: 0, inApp: 0, skippedNoPhone: 0 };
  const seen = new Set<number>();

  for (const nurse of input.nurses) {
    if (!isApprovedHomeCareNurse(nurse)) continue;
    const userId = Number(nurse.id);
    if (!Number.isFinite(userId) || userId <= 0 || seen.has(userId)) continue;
    seen.add(userId);

    const one = await notify({
      nurses: [nurse],
      title: input.title,
      location: input.location,
      token: input.token,
      sendSMS: input.sendSMS,
      writeNotification: input.writeNotification,
      sendPush: input.sendPush,
    });
    totals.sms += one.sms;
    totals.inApp += one.inApp;
    totals.skippedNoPhone += one.skippedNoPhone;
  }

  return totals;
}
