import type { Express, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import type { PoolClient, QueryResult } from 'pg';
import { pool, query } from './db';
import { authenticate, requireRoles, type AuthedRequest } from './authz';
import { GHANA_REGIONS } from './phase5';

type Sql = (text: string, params?: unknown[]) => Promise<QueryResult>;

const SPECIALIZATIONS = [
  'General practice',
  'Paediatrics',
  'Internal medicine',
  'Obstetrics',
  'Mental health',
  'Other',
] as const;

const PRACTICE_AREAS = [
  'General nursing',
  'Midwifery',
  'Triage',
  'Community',
  'Other',
] as const;

const WORKING_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const REGION_NAMES = new Set(GHANA_REGIONS.map((r) => r.name.toLowerCase()));

/** Local Ghana mobile: 0 + 9 digits. Accepts 0XXXXXXXXX, 233XXXXXXXXX, +233…, or 9 digits. */
export function normalizeGhanaPhone(raw: unknown): string | null {
  let d = String(raw ?? '').trim().replace(/[\s\-().]/g, '');
  if (d.startsWith('+')) d = d.slice(1);
  if (!/^\d+$/.test(d)) return null;
  if (d.startsWith('233') && d.length === 12) d = `0${d.slice(3)}`;
  else if (d.length === 9) d = `0${d}`;
  if (!/^0\d{9}$/.test(d)) return null;
  return d;
}

export function ghanaPhoneVariants(local: string): string[] {
  const intl = `233${local.slice(1)}`;
  return [local, intl, `+${intl}`];
}

export const PHONE_INVALID_MESSAGE =
  'Enter a valid mobile number. Ghana numbers can start with 0. Other countries need a country code, such as +1.';

/**
 * Ghana mobiles stay 0XXXXXXXXX. Anything else must be E.164 (+ and 8–15 digits).
 * A +233 number that is a real Ghana mobile is stored in the local form.
 */
export function normalizeAccountPhone(raw: unknown): string | null {
  const ghana = normalizeGhanaPhone(raw);
  if (ghana) return ghana;
  const text = String(raw ?? '').trim().replace(/[\s\-().]/g, '');
  if (!text.startsWith('+')) return null;
  const digits = text.slice(1);
  if (!/^\d{8,15}$/.test(digits)) return null;
  if (digits.startsWith('233')) return null;
  return `+${digits}`;
}

export function accountPhoneVariants(stored: string): string[] {
  if (/^0\d{9}$/.test(stored)) return ghanaPhoneVariants(stored);
  const digits = stored.replace(/\D/g, '');
  if (!digits) return [stored];
  return Array.from(new Set([stored, `+${digits}`, digits]));
}

export function phoneMatchKeys(raw: unknown): string[] {
  const text = String(raw ?? '').trim();
  const canonical = normalizeAccountPhone(text);
  const variants = canonical ? accountPhoneVariants(canonical) : [];
  return Array.from(new Set([text, canonical, ...variants].filter((v): v is string => Boolean(v && v.length))));
}

function canonicalRegion(raw: unknown): string | null {
  const text = String(raw ?? '').trim();
  if (!text) return null;
  const hit = GHANA_REGIONS.find((r) => r.name.toLowerCase() === text.toLowerCase());
  return hit?.name ?? (REGION_NAMES.has(text.toLowerCase()) ? text : null);
}

function clip(raw: unknown, max: number): string {
  return String(raw ?? '').trim().slice(0, max);
}

const OTHER_COUNTRY = 'Other country';

/** Ghana agencies keep one of the 16 regions. Elsewhere, store the country name. */
function resolveAgencyRegion(body: { region?: unknown; country?: unknown }): { region: string } | { error: string } {
  const country = clip(body.country, 80);
  const regionText = clip(body.region, 80);
  const ghana = canonicalRegion(regionText);
  const countryIsOther =
    country.length > 0 &&
    country.toLowerCase() !== 'ghana' &&
    country.toLowerCase() !== OTHER_COUNTRY.toLowerCase();
  if (ghana && !countryIsOther) return { region: ghana };
  if (regionText.toLowerCase() === OTHER_COUNTRY.toLowerCase() || countryIsOther) {
    if (!countryIsOther) return { error: 'Enter the country where the agency operates' };
    return { region: country };
  }
  return { error: "Choose one of Ghana's 16 regions, or Other country" };
}

async function withTransaction<T>(fn: (q: Sql) => Promise<T>): Promise<T> {
  const client: PoolClient = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn((text, params) => client.query(text, params));
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch {
      /* rollback already failed */
    }
    throw err;
  } finally {
    client.release();
  }
}

async function phoneTaken(q: Sql, local: string): Promise<boolean> {
  const variants = accountPhoneVariants(local);
  const digits = variants.map((v) => v.replace(/\D/g, ''));
  const found = await q(
    `SELECT id FROM users
     WHERE username = ANY($1::text[])
        OR phone_number = ANY($1::text[])
        OR regexp_replace(COALESCE(phone_number, ''), '[^0-9]', '', 'g') = ANY($2::text[])
        OR regexp_replace(COALESCE(username, ''), '[^0-9]', '', 'g') = ANY($2::text[])
     LIMIT 1`,
    [variants, digits]
  );
  return found.rows.length > 0;
}

function issueSession(
  user: {
    id: number;
    username: string;
    role: string;
    name: string;
    phone_number: string | null;
    email?: string | null;
    verification_status?: string | null;
  },
  extras: Record<string, unknown> = {}
) {
  const token = jwt.sign(
    { id: user.id, username: user.username, role: user.role },
    process.env.JWT_SECRET!,
    { expiresIn: '24h' }
  );
  return {
    token,
    user: {
      id: user.id,
      username: user.username,
      role: user.role,
      name: user.name,
      phone_number: user.phone_number,
      email: user.email ?? null,
      verification_status: user.verification_status || 'pending',
      ...extras,
    },
  };
}

function httpError(status: number, message: string): Error & { status?: number } {
  const error = new Error(message) as Error & { status?: number };
  error.status = status;
  return error;
}

function rejectSignupError(res: { status: (code: number) => { json: (body: unknown) => void } }, err: unknown) {
  const code = (err as { code?: string })?.code;
  if (code === '23505') {
    return res.status(409).json({ message: 'An account already exists for this phone number' });
  }
  console.error('professional signup failed', code || 'error');
  return res.status(500).json({ message: 'Could not create the account' });
}

export function registerProfessionalSignupRoutes(app: Express) {
  app.post('/api/auth/signup/doctor', async (req, res) => {
    const body = req.body || {};
    const fullName = clip(body.fullName, 100);
    const phone = normalizeAccountPhone(body.phone);
    const password = typeof body.password === 'string' ? body.password : '';
    const specialization = String(body.specialization || '').trim();
    const licenseNumber = clip(body.licenseNumber, 80);
    const facility = clip(body.facility, 120) || 'Healynks Virtual Clinic';

    if (!fullName) return res.status(400).json({ message: 'Full name is required' });
    if (!phone) return res.status(400).json({ message: PHONE_INVALID_MESSAGE });
    if (password.length < 8) return res.status(400).json({ message: 'Password must be at least 8 characters' });
    if (!SPECIALIZATIONS.includes(specialization as (typeof SPECIALIZATIONS)[number])) {
      return res.status(400).json({ message: 'Choose a specialization' });
    }

    try {
      const session = await withTransaction(async (q) => {
        if (await phoneTaken(q, phone)) {
          const error = new Error('duplicate') as Error & { status?: number };
          error.status = 409;
          throw error;
        }
        const hashed = await bcrypt.hash(password, 10);
        const userResult = await q(
          `INSERT INTO users (username, password, role, name, phone_number, verification_status)
           VALUES ($1, $2, 'doctor', $3, $1, 'pending')
           RETURNING id, username, role, name, phone_number, email, verification_status`,
          [phone, hashed, fullName]
        );
        const user = userResult.rows[0];
        await q(
          `INSERT INTO doctors (
             user_id, name, specialization, slot_duration, start_time, end_time, working_days,
             title, languages, consultation_fee, facility, is_active, is_online,
             registration_number, verification_status
           ) VALUES (
             $1, $2, $3, 30, '09:00', '17:00', $4,
             'Dr', 'English', 120, $5, TRUE, FALSE,
             $6, 'pending'
           )`,
          [user.id, fullName, specialization, WORKING_DAYS, facility, licenseNumber || null]
        );
        return issueSession(user);
      });
      res.status(201).json(session);
    } catch (err) {
      const status = (err as { status?: number })?.status;
      if (status === 409) {
        return res.status(409).json({ message: 'An account already exists for this phone number' });
      }
      return rejectSignupError(res, err);
    }
  });

  app.post('/api/auth/signup/nurse', async (req, res) => {
    const body = req.body || {};
    const fullName = clip(body.fullName, 100);
    const phone = normalizeAccountPhone(body.phone);
    const password = typeof body.password === 'string' ? body.password : '';
    const practiceArea = String(body.practiceArea || '').trim();
    const licenseNumber = clip(body.licenseNumber, 80);
    const facility = clip(body.facility, 120) || 'Healynks Virtual Clinic';

    if (!fullName) return res.status(400).json({ message: 'Full name is required' });
    if (!phone) return res.status(400).json({ message: PHONE_INVALID_MESSAGE });
    if (password.length < 8) return res.status(400).json({ message: 'Password must be at least 8 characters' });
    if (!PRACTICE_AREAS.includes(practiceArea as (typeof PRACTICE_AREAS)[number])) {
      return res.status(400).json({ message: 'Choose a unit or area of practice' });
    }

    try {
      const session = await withTransaction(async (q) => {
        if (await phoneTaken(q, phone)) {
          const error = new Error('duplicate') as Error & { status?: number };
          error.status = 409;
          throw error;
        }
        const hashed = await bcrypt.hash(password, 10);
        const userResult = await q(
          `INSERT INTO users (username, password, role, name, phone_number, verification_status)
           VALUES ($1, $2, 'nurse', $3, $1, 'pending')
           RETURNING id, username, role, name, phone_number, email, verification_status`,
          [phone, hashed, fullName]
        );
        const user = userResult.rows[0];
        await q(
          `INSERT INTO nurses (
             user_id, name, practice_area, facility, registration_number, verification_status, is_active
           ) VALUES ($1, $2, $3, $4, $5, 'pending', TRUE)`,
          [user.id, fullName, practiceArea, facility, licenseNumber || null]
        );
        return issueSession(user);
      });
      res.status(201).json(session);
    } catch (err) {
      const status = (err as { status?: number })?.status;
      if (status === 409) {
        return res.status(409).json({ message: 'An account already exists for this phone number' });
      }
      return rejectSignupError(res, err);
    }
  });

  app.post('/api/auth/signup/agency', async (req, res) => {
    const body = req.body || {};
    const fullName = clip(body.fullName, 100);
    const phone = normalizeAccountPhone(body.phone);
    const password = typeof body.password === 'string' ? body.password : '';
    const agencyName = clip(body.agencyName, 160);
    const place = resolveAgencyRegion(body);
    const town = clip(body.town, 80);
    const address = clip(body.address, 400);

    if (!fullName) return res.status(400).json({ message: 'Full name is required' });
    if (!phone) return res.status(400).json({ message: PHONE_INVALID_MESSAGE });
    if (password.length < 8) return res.status(400).json({ message: 'Password must be at least 8 characters' });
    if (!agencyName) return res.status(400).json({ message: 'Agency name is required' });
    if ('error' in place) return res.status(400).json({ message: place.error });
    const region = place.region;
    if (!town) return res.status(400).json({ message: 'Town is required' });

    try {
      const session = await withTransaction(async (q) => {
        if (await phoneTaken(q, phone)) {
          const error = new Error('duplicate') as Error & { status?: number };
          error.status = 409;
          throw error;
        }
        const hashed = await bcrypt.hash(password, 10);
        const userResult = await q(
          `INSERT INTO users (username, password, role, name, phone_number, verification_status)
           VALUES ($1, $2, 'nurse', $3, $1, 'pending')
           RETURNING id, username, role, name, phone_number, email, verification_status`,
          [phone, hashed, fullName]
        );
        const user = userResult.rows[0];
        await q(
          `INSERT INTO nurse_agencies (name, region, town, address, phone, owner_user_id)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [agencyName, region, town, address || null, phone, user.id]
        );
        return issueSession(user, { agency_name: agencyName });
      });
      res.status(201).json(session);
    } catch (err) {
      const status = (err as { status?: number })?.status;
      if (status === 409) {
        return res.status(409).json({ message: 'An account already exists for this phone number' });
      }
      return rejectSignupError(res, err);
    }
  });

  app.get('/api/admin/signups', authenticate, requireRoles('admin'), async (_req, res) => {
    try {
      const doctors = await query(
        `SELECT u.id AS user_id, u.name, u.phone_number AS phone, d.specialization AS specialty, u.created_at
         FROM users u
         JOIN doctors d ON d.user_id = u.id
         WHERE u.role = 'doctor' AND u.verification_status = 'pending'
         ORDER BY u.created_at DESC NULLS LAST, u.id DESC`
      );
      const nurses = await query(
        `SELECT u.id AS user_id, u.name, u.phone_number AS phone, n.practice_area AS specialty, u.created_at
         FROM users u
         JOIN nurses n ON n.user_id = u.id
         WHERE u.role = 'nurse'
           AND u.verification_status = 'pending'
           AND NOT EXISTS (SELECT 1 FROM nurse_agencies a WHERE a.owner_user_id = u.id)
         ORDER BY u.created_at DESC NULLS LAST, u.id DESC`
      );
      const agencies = await query(
        `SELECT u.id AS user_id,
                u.name,
                u.phone_number AS phone,
                a.name AS agency_name,
                a.region,
                a.town,
                COALESCE(a.created_at, u.created_at) AS created_at
         FROM nurse_agencies a
         JOIN users u ON u.id = a.owner_user_id
         WHERE u.verification_status = 'pending'
         ORDER BY a.created_at DESC NULLS LAST, a.id DESC`
      );
      const clinician = (row: { user_id: number; name: string; phone: string; specialty: string; created_at: unknown }) => ({
        user_id: row.user_id,
        name: row.name,
        phone: row.phone,
        specialty: row.specialty,
        region: null,
        town: null,
        created_at: row.created_at,
      });
      res.json({
        doctors: doctors.rows.map(clinician),
        nurses: nurses.rows.map(clinician),
        agencies: agencies.rows.map((row) => ({
          user_id: row.user_id,
          name: row.name,
          phone: row.phone,
          agency_name: row.agency_name,
          region: row.region,
          town: row.town,
          created_at: row.created_at,
        })),
      });
    } catch (err) {
      console.error('admin signups failed', (err as { code?: string })?.code || 'error');
      res.status(500).json({ message: 'Server error' });
    }
  });

  const decideSignup = async (req: AuthedRequest, res: Response) => {
    const userId = Number(req.params.userId);
    const decision = String(req.body?.decision || '').trim().toLowerCase();
    if (!Number.isFinite(userId) || userId <= 0) {
      return res.status(400).json({ message: 'A valid user id is required' });
    }
    if (decision !== 'approve' && decision !== 'reject') {
      return res.status(400).json({ message: 'Decision must be approve or reject' });
    }

    const approved = decision === 'approve';
    const status = approved ? 'approved' : 'rejected';

    try {
      const result = await withTransaction(async (q) => {
        const userRes = await q(
          `SELECT id, role, verification_status FROM users WHERE id = $1 FOR UPDATE`,
          [userId]
        );
        const user = userRes.rows[0];
        if (!user) throw httpError(404, 'No signup found for this account');

        const doctor = await q(`SELECT id FROM doctors WHERE user_id = $1 LIMIT 1`, [userId]);
        const agency = await q(`SELECT id FROM nurse_agencies WHERE owner_user_id = $1 LIMIT 1`, [userId]);
        const nurse = await q(`SELECT id FROM nurses WHERE user_id = $1 LIMIT 1`, [userId]);
        const isDoctor = user.role === 'doctor' && Boolean(doctor.rows[0]);
        const isAgency = user.role === 'nurse' && Boolean(agency.rows[0]);
        const isNurse = user.role === 'nurse' && Boolean(nurse.rows[0]) && !isAgency;
        if (!isDoctor && !isAgency && !isNurse) throw httpError(404, 'No signup found for this account');
        if (user.verification_status !== 'pending') {
          throw httpError(409, 'This signup has already been reviewed');
        }

        const notice = isNurse
          ? approved
            ? {
                title: 'Healynks approved your nurse profile',
                message: 'Healynks approved your nurse profile. You can practice on Healynks.',
              }
            : {
                title: 'Healynks did not approve your nurse profile',
                message: 'Your Healynks nurse profile was not approved. Contact Healynks support.',
              }
          : approved
            ? {
                title: 'Healynks approved your profile',
                message: 'Healynks approved your profile',
              }
            : {
                title: 'Healynks did not approve your profile',
                message: 'Your Healynks profile was not approved. Contact Healynks support.',
              };

        await q(`UPDATE users SET verification_status = $1 WHERE id = $2`, [status, userId]);
        if (isDoctor) {
          await q(
            `UPDATE doctors
             SET verification_status = $1,
                 is_active = $2,
                 is_online = CASE WHEN $2 THEN is_online ELSE FALSE END
             WHERE user_id = $3`,
            [status, approved, userId]
          );
        }
        if (isNurse) {
          await q(
            `UPDATE nurses
             SET verification_status = $1,
                 is_active = $2
             WHERE user_id = $3`,
            [status, approved, userId]
          );
        }
        await q(
          `INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, 'verification')`,
          [userId, notice.title, notice.message]
        );
        return {
          user_id: userId,
          role: user.role,
          decision,
          verification_status: status,
          is_active: isDoctor || isNurse ? approved : null,
        };
      });
      res.json(result);
    } catch (err) {
      const statusCode = (err as { status?: number })?.status;
      if (statusCode) return res.status(statusCode).json({ message: (err as Error).message });
      console.error('signup decision failed', (err as { code?: string })?.code || 'error');
      res.status(500).json({ message: 'Server error' });
    }
  };

  app.post('/api/admin/signups/:userId', authenticate, requireRoles('admin'), decideSignup);
  app.patch('/api/admin/signups/:userId', authenticate, requireRoles('admin'), decideSignup);

  app.get('/api/agency/me', authenticate, requireRoles('nurse'), async (req: AuthedRequest, res) => {
    try {
      const result = await query(
        `SELECT a.name, a.region, a.town, a.address, a.phone, u.verification_status
         FROM nurse_agencies a
         JOIN users u ON u.id = a.owner_user_id
         WHERE a.owner_user_id = $1
         LIMIT 1`,
        [req.user!.id]
      );
      const row = result.rows[0];
      if (!row) return res.status(404).json({ message: 'No agency for this account' });
      res.json({
        name: row.name,
        region: row.region,
        town: row.town,
        address: row.address,
        phone: row.phone,
        verification_status: row.verification_status || 'pending',
      });
    } catch (err) {
      console.error('agency profile failed', (err as { code?: string })?.code || 'error');
      res.status(500).json({ message: 'Server error' });
    }
  });
}
