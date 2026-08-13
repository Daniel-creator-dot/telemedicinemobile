import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { query } from './db';
import { getAccessiblePatientIds, getPatientForUser } from './patients';

export type AuthedUser = { id: number; username: string; role: string };
export type AuthedRequest = Request & { user?: AuthedUser };

export const CLINICAL_STAFF = ['doctor', 'nurse', 'medical_ops', 'admin'];
export const CARE_NETWORK = ['lab_technician', 'pharmacy', 'imaging', 'nurse', 'medical_ops', 'admin', 'doctor'];
export const ADMIN_OPS = ['admin', 'medical_ops'];

const otpBuckets = new Map<string, { count: number; resetAt: number; fails: number; lockedUntil: number }>();

export function authenticate(req: AuthedRequest, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ message: 'No token provided' });

  const token = authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ message: 'No token provided' });

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET!) as AuthedUser;
    req.user = { id: decoded.id, username: decoded.username, role: decoded.role };
    next();
  } catch {
    res.status(401).json({ message: 'Invalid token' });
  }
}

export function requireRoles(...roles: string[]) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    if (!req.user) return res.status(401).json({ message: 'No token provided' });
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    next();
  };
}

export async function getDoctorForUser(userId: number) {
  const result = await query('SELECT * FROM doctors WHERE user_id = $1', [userId]);
  return result.rows[0] || null;
}

export async function canAccessAppointment(user: AuthedUser, apt: any): Promise<boolean> {
  if (!apt) return false;
  if (['admin', 'medical_ops', 'nurse'].includes(user.role)) return true;

  if (user.role === 'doctor') {
    const doc = await getDoctorForUser(user.id);
    if (!doc) return false;
    return !apt.doctor_id || Number(apt.doctor_id) === Number(doc.id);
  }

  if (user.role === 'patient') {
    const ids = await getAccessiblePatientIds(user.id);
    const userRow = await query('SELECT phone_number FROM users WHERE id = $1', [user.id]);
    const phone = userRow.rows[0]?.phone_number;
    return Boolean(
      (apt.patient_id && ids.includes(Number(apt.patient_id))) ||
        (phone && apt.phone_number === phone)
    );
  }

  return false;
}

export async function assertAppointmentAccess(req: AuthedRequest, res: Response, appointmentId: string | number) {
  if (!req.user) {
    res.status(401).json({ message: 'No token provided' });
    return null;
  }
  const result = await query(
    `SELECT a.*, d.name as doctor_name
     FROM appointments a
     LEFT JOIN doctors d ON a.doctor_id = d.id
     WHERE a.id = $1`,
    [appointmentId]
  );
  const apt = result.rows[0];
  if (!apt) {
    res.status(404).json({ message: 'Not found' });
    return null;
  }
  const ok = await canAccessAppointment(req.user, apt);
  if (!ok) {
    res.status(403).json({ message: 'Forbidden' });
    return null;
  }
  return apt;
}

export async function canAccessPatient(user: AuthedUser, patientId: number | string): Promise<boolean> {
  if (['admin', 'medical_ops', 'nurse', 'doctor'].includes(user.role)) return true;
  if (user.role === 'patient') {
    const ids = await getAccessiblePatientIds(user.id);
    return ids.includes(Number(patientId));
  }
  return false;
}

export function checkOtpRateLimit(key: string, kind: 'request' | 'verify'): { ok: boolean; retryAfterSec?: number } {
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const maxRequests = 5;
  const maxFails = 5;
  let bucket = otpBuckets.get(key);
  if (!bucket || now > bucket.resetAt) {
    bucket = { count: 0, resetAt: now + windowMs, fails: 0, lockedUntil: 0 };
    otpBuckets.set(key, bucket);
  }
  if (bucket.lockedUntil > now) {
    return { ok: false, retryAfterSec: Math.ceil((bucket.lockedUntil - now) / 1000) };
  }
  if (kind === 'request') {
    if (bucket.count >= maxRequests) {
      bucket.lockedUntil = now + windowMs;
      return { ok: false, retryAfterSec: Math.ceil(windowMs / 1000) };
    }
    bucket.count += 1;
    return { ok: true };
  }
  return { ok: true, retryAfterSec: undefined };
}

export function recordOtpFailure(key: string) {
  const now = Date.now();
  const bucket = otpBuckets.get(key) || { count: 0, resetAt: now + 15 * 60 * 1000, fails: 0, lockedUntil: 0 };
  bucket.fails += 1;
  if (bucket.fails >= 5) {
    bucket.lockedUntil = now + 15 * 60 * 1000;
  }
  otpBuckets.set(key, bucket);
}

export function clearOtpFailures(key: string) {
  otpBuckets.delete(key);
}

export function publicSettings(rows: { key: string; value: string }[], role?: string) {
  const settings = rows.reduce((acc: Record<string, string>, row) => {
    acc[row.key] = row.value;
    return acc;
  }, {});
  if (role !== 'admin') {
    delete settings.sms_api_key;
    delete settings.sms_base_url;
    delete settings.paystack_secret_key;
  } else {
    if (settings.sms_api_key) {
      settings.sms_api_key_set = 'true';
      settings.sms_api_key = '********';
    }
    if (settings.paystack_secret_key) {
      settings.paystack_secret_key_set = 'true';
      settings.paystack_secret_key = '********';
    }
  }
  return settings;
}

export function appointmentScopeSql(role: string, alias = 'a') {
  if (['admin', 'medical_ops', 'nurse'].includes(role)) {
    return { clause: '', params: [] as unknown[] };
  }
  if (role === 'doctor') {
    return {
      clause: ` WHERE ${alias}.doctor_id = $1`,
      params: [] as unknown[],
      needsDoctorId: true,
    };
  }
  if (role === 'patient') {
    return {
      clause: ` WHERE ($1::int IS NOT NULL AND ${alias}.patient_id = $1) OR ${alias}.phone_number = $2`,
      params: [] as unknown[],
      needsPatient: true,
    };
  }
  return { clause: ' WHERE FALSE', params: [] as unknown[] };
}
