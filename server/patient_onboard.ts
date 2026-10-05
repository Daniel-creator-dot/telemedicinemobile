import crypto from 'crypto';
import type { Express, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import type { AuthedRequest } from './authz';
import { pool, query } from './db';
import { normalizeAccountPhone, phoneMatchKeys, PHONE_INVALID_MESSAGE } from './professional_signup';
import { sendSMS } from './sms';

export const DUPLICATE_PHONE_MESSAGE = 'This phone already has a Healynks record.';

/** Never text this number from staff onboarding. */
const BLOCKED_ONBOARD_PHONE = '0247904675';

const PASSWORD_WORDS = ['River', 'Garden', 'Market', 'Gentle', 'Sunday', 'Family', 'Morning', 'Candle', 'Orange', 'Meadow'];

export function onboardFieldError(body: { full_name?: unknown; phone?: unknown }): string | null {
  const name = String(body.full_name ?? '').trim();
  const phone = String(body.phone ?? '').trim();
  if (!name) return "Enter the patient's full name.";
  if (!phone) return "Enter the patient's mobile number.";
  return null;
}

export function canStaffOnboard(role: string | null | undefined, verificationStatus: string | null | undefined): boolean {
  const normalized = String(role || '').trim().toLowerCase();
  if (normalized === 'admin' || normalized === 'doctor') return true;
  if (normalized === 'nurse') {
    return String(verificationStatus || '').trim().toLowerCase() === 'approved';
  }
  return false;
}

export function canTextOnboardPhone(phone: string): boolean {
  const normalized = normalizeAccountPhone(phone);
  if (!normalized) return false;
  return normalized !== BLOCKED_ONBOARD_PHONE;
}

export function onboardSmsText(staffName: string): string {
  const name = String(staffName || '').replace(/\s+/g, ' ').trim().slice(0, 40) || 'Your care team';
  return `Healynks: ${name} started your care record. Open https://healynks.app/login and sign in with this phone.`;
}

export function readableSignInPassword(word: string, digits: number): string {
  return `${word}${digits}`;
}

function newSignInPassword(): string {
  const word = PASSWORD_WORDS[crypto.randomInt(PASSWORD_WORDS.length)];
  const digits = crypto.randomInt(1000, 10000);
  return readableSignInPassword(word, digits);
}

function clip(raw: unknown, max: number): string {
  return String(raw ?? '').trim().slice(0, max);
}

function isUniqueViolation(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { code?: string }).code === '23505';
}

async function gatewayConfigured(): Promise<boolean> {
  const row = await query(`SELECT value FROM settings WHERE key = 'sms_base_url'`);
  return String(row.rows[0]?.value || '').trim().length > 0;
}

export function registerPatientOnboardRoutes(
  app: Express,
  authenticate: (req: AuthedRequest, res: Response, next: NextFunction) => void
) {
  app.get('/api/patients/onboard', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const staff = await loadStaff(req.user!.id);
      if (!staff || !canStaffOnboard(staff.role, staff.verification_status)) {
        return res.status(403).json({ message: 'You need an approved staff account to add a patient.' });
      }
      const rows = await query(
        `SELECT full_name, phone_number
         FROM patients
         WHERE onboarded_by = $1
         ORDER BY created_at DESC NULLS LAST, id DESC`,
        [staff.id]
      );
      return res.json({
        patients: rows.rows.map((row: { full_name: string; phone_number: string }) => ({
          full_name: row.full_name,
          phone_number: row.phone_number,
        })),
      });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ message: 'We could not load the patients you added.' });
    }
  });

  app.post('/api/patients/onboard', authenticate, async (req: AuthedRequest, res: Response) => {
    const body = (req.body || {}) as {
      full_name?: unknown;
      fullName?: unknown;
      phone?: unknown;
      phone_number?: unknown;
      family_name?: unknown;
      family_phone?: unknown;
      town?: unknown;
    };
    const fullName = clip(body.full_name ?? body.fullName, 100);
    const phoneRaw = String(body.phone ?? body.phone_number ?? '').trim();
    const missing = onboardFieldError({ full_name: fullName, phone: phoneRaw });
    if (missing) return res.status(400).json({ message: missing });

    const phone = normalizeAccountPhone(phoneRaw);
    if (!phone) return res.status(400).json({ message: PHONE_INVALID_MESSAGE });

    const familyName = clip(body.family_name, 100);
    const familyPhoneRaw = String(body.family_phone ?? '').trim();
    let familyPhone: string | null = null;
    if (familyPhoneRaw) {
      familyPhone = normalizeAccountPhone(familyPhoneRaw);
      if (!familyPhone) {
        return res.status(400).json({ message: 'Enter a family mobile number, or leave it blank.' });
      }
    }
    const town = clip(body.town, 80);

    try {
      const staff = await loadStaff(req.user!.id);
      if (!staff || !canStaffOnboard(staff.role, staff.verification_status)) {
        return res.status(403).json({ message: 'You need an approved staff account to add a patient.' });
      }

      const signInPassword = newSignInPassword();
      const created = await createPatientAccount({
        staffId: staff.id,
        fullName,
        phone,
        familyName: familyName || null,
        familyPhone,
        town: town || null,
        signInPassword,
      });
      if ('conflict' in created) {
        return res.status(409).json({ message: DUPLICATE_PHONE_MESSAGE });
      }

      const smsSent = await textPatientOnce(phone, staff.name);
      return res.status(201).json({
        patient: {
          full_name: created.full_name,
          phone_number: created.phone_number,
        },
        sms_sent: smsSent,
        sign_in_password: signInPassword,
      });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ message: 'We could not save this patient. Try again.' });
    }
  });
}

async function loadStaff(userId: number): Promise<{
  id: number;
  role: string;
  name: string;
  verification_status: string | null;
} | null> {
  const result = await query(
    `SELECT id, role, name, verification_status FROM users WHERE id = $1`,
    [userId]
  );
  const row = result.rows[0];
  if (!row) return null;
  return {
    id: Number(row.id),
    role: String(row.role || ''),
    name: String(row.name || ''),
    verification_status: row.verification_status ? String(row.verification_status) : null,
  };
}

async function phoneTaken(phone: string): Promise<boolean> {
  const keys = phoneMatchKeys(phone);
  const existing = await query(
    `SELECT 1 FROM users WHERE phone_number = ANY($1::text[]) OR username = ANY($1::text[])
     UNION ALL
     SELECT 1 FROM patients WHERE phone_number = ANY($1::text[])
     LIMIT 1`,
    [keys]
  );
  return existing.rows.length > 0;
}

async function createPatientAccount(input: {
  staffId: number;
  fullName: string;
  phone: string;
  familyName: string | null;
  familyPhone: string | null;
  town: string | null;
  signInPassword: string;
}): Promise<{ full_name: string; phone_number: string } | { conflict: true }> {
  if (await phoneTaken(input.phone)) return { conflict: true };

  const hashed = await bcrypt.hash(input.signInPassword, 10);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const keys = phoneMatchKeys(input.phone);
    const again = await client.query(
      `SELECT 1 FROM users WHERE phone_number = ANY($1::text[]) OR username = ANY($1::text[])
       UNION ALL
       SELECT 1 FROM patients WHERE phone_number = ANY($1::text[])
       LIMIT 1`,
      [keys]
    );
    if (again.rows.length > 0) {
      await client.query('ROLLBACK');
      return { conflict: true };
    }

    const userResult = await client.query(
      `INSERT INTO users (username, password, role, name, phone_number)
       VALUES ($1, $2, 'patient', $3, $4)
       RETURNING id`,
      [input.phone, hashed, input.fullName, input.phone]
    );
    const userId = Number(userResult.rows[0].id);
    const codeResult = await client.query(`SELECT nextval('patient_code_seq') AS n`);
    const patientCode = `DH-${String(codeResult.rows[0].n).padStart(6, '0')}`;
    const patientResult = await client.query(
      `INSERT INTO patients (
         user_id, patient_code, full_name, phone_number, town,
         emergency_name, emergency_phone, onboarded_by
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING full_name, phone_number`,
      [
        userId,
        patientCode,
        input.fullName,
        input.phone,
        input.town,
        input.familyName,
        input.familyPhone,
        input.staffId,
      ]
    );
    await client.query('COMMIT');
    return {
      full_name: String(patientResult.rows[0].full_name),
      phone_number: String(patientResult.rows[0].phone_number),
    };
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {
      /* already closed */
    }
    if (isUniqueViolation(err)) return { conflict: true };
    throw err;
  } finally {
    client.release();
  }
}

/** One text to the patient phone, and only when the gateway has a base URL. */
async function textPatientOnce(phone: string, staffName: string): Promise<boolean> {
  if (!canTextOnboardPhone(phone)) return false;
  try {
    if (!(await gatewayConfigured())) return false;
    const message = onboardSmsText(staffName);
    await sendSMS(phone, message);
    const log = await query(
      `SELECT status FROM sms_logs WHERE recipient = $1 AND message = $2 ORDER BY id DESC LIMIT 1`,
      [phone.slice(0, 20), message]
    );
    return String(log.rows[0]?.status || '') === 'sent';
  } catch (err) {
    console.error('Onboard SMS skipped', err instanceof Error ? err.message : 'failed');
    return false;
  }
}
