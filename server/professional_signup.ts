import type { Express } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import type { PoolClient, QueryResult } from 'pg';
import { pool, query } from './db';
import { authenticate, requireRoles } from './authz';
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

function canonicalRegion(raw: unknown): string | null {
  const text = String(raw ?? '').trim();
  if (!text) return null;
  const hit = GHANA_REGIONS.find((r) => r.name.toLowerCase() === text.toLowerCase());
  return hit?.name ?? (REGION_NAMES.has(text.toLowerCase()) ? text : null);
}

function clip(raw: unknown, max: number): string {
  return String(raw ?? '').trim().slice(0, max);
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
  const variants = ghanaPhoneVariants(local);
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
    const phone = normalizeGhanaPhone(body.phone);
    const password = typeof body.password === 'string' ? body.password : '';
    const specialization = String(body.specialization || '').trim();
    const licenseNumber = clip(body.licenseNumber, 80);
    const facility = clip(body.facility, 120) || 'Healynks Virtual Clinic';

    if (!fullName) return res.status(400).json({ message: 'Full name is required' });
    if (!phone) return res.status(400).json({ message: 'Enter a valid Ghana mobile number' });
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

  app.post('/api/auth/signup/agency', async (req, res) => {
    const body = req.body || {};
    const fullName = clip(body.fullName, 100);
    const phone = normalizeGhanaPhone(body.phone);
    const password = typeof body.password === 'string' ? body.password : '';
    const agencyName = clip(body.agencyName, 160);
    const region = canonicalRegion(body.region);
    const town = clip(body.town, 80);
    const address = clip(body.address, 400);

    if (!fullName) return res.status(400).json({ message: 'Full name is required' });
    if (!phone) return res.status(400).json({ message: 'Enter a valid Ghana mobile number' });
    if (password.length < 8) return res.status(400).json({ message: 'Password must be at least 8 characters' });
    if (!agencyName) return res.status(400).json({ message: 'Agency name is required' });
    if (!region) return res.status(400).json({ message: "Choose one of Ghana's 16 regions" });
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
        `SELECT u.name, u.phone_number AS phone, d.specialization AS specialty, u.created_at
         FROM users u
         JOIN doctors d ON d.user_id = u.id
         WHERE u.role = 'doctor' AND u.verification_status = 'pending'
         ORDER BY u.created_at DESC NULLS LAST, u.id DESC`
      );
      const agencies = await query(
        `SELECT u.name,
                u.phone_number AS phone,
                a.name AS agency_name,
                COALESCE(a.created_at, u.created_at) AS created_at
         FROM nurse_agencies a
         JOIN users u ON u.id = a.owner_user_id
         WHERE u.verification_status = 'pending'
         ORDER BY a.created_at DESC NULLS LAST, a.id DESC`
      );
      res.json({
        doctors: doctors.rows.map((row) => ({
          name: row.name,
          phone: row.phone,
          specialty: row.specialty,
          created_at: row.created_at,
        })),
        agencies: agencies.rows.map((row) => ({
          name: row.name,
          phone: row.phone,
          agency_name: row.agency_name,
          created_at: row.created_at,
        })),
      });
    } catch (err) {
      console.error('admin signups failed', (err as { code?: string })?.code || 'error');
      res.status(500).json({ message: 'Server error' });
    }
  });
}
