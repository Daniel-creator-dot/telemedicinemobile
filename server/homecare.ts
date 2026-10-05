import type { Express, Response } from 'express';
import { pool, query } from './db';
import { authenticate, type AuthedRequest } from './authz';
import { normalizeAccountPhone, PHONE_INVALID_MESSAGE } from './professional_signup';

/**
 * Home-care request board.
 * Admins post a visit. Approved nurses and nurse-agency owners claim it in the app.
 * No payment and no SMS broadcast.
 */

type Viewer = {
  id: number;
  role: string;
  name: string;
  verification_status: string | null;
  nurse_active: boolean | null;
  has_nurse_row: boolean;
  agency_name: string | null;
  agency_town: string | null;
  nurse_town: string | null;
};

const LIST_SQL = `
  SELECT r.*,
         creator.name AS created_by_name,
         claimer.name AS claimed_name,
         agency.name AS claimed_agency_name,
         patient.full_name AS patient_name,
         referrer.name AS referrer_name
  FROM home_care_requests r
  LEFT JOIN users creator ON creator.id = r.created_by
  LEFT JOIN users claimer ON claimer.id = r.claimed_by
  LEFT JOIN nurse_agencies agency ON agency.owner_user_id = r.claimed_by
  LEFT JOIN patients patient ON patient.id = r.patient_id
  LEFT JOIN users referrer ON referrer.id = r.referrer_user_id
`;

export async function initHomeCareSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS home_care_requests (
      id SERIAL PRIMARY KEY,
      title VARCHAR(160) NOT NULL,
      location TEXT NOT NULL,
      contact_phone VARCHAR(40) NOT NULL,
      note TEXT,
      status VARCHAR(20) NOT NULL DEFAULT 'open',
      created_by INTEGER REFERENCES users(id),
      claimed_by INTEGER REFERENCES users(id),
      claimed_at TIMESTAMP,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS home_care_requests_status_idx ON home_care_requests (status);
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS home_care_requests_claimed_by_idx ON home_care_requests (claimed_by);
  `);
  await query(`
    ALTER TABLE nurses ADD COLUMN IF NOT EXISTS town VARCHAR(80);
  `);
  await query(`
    CREATE TABLE IF NOT EXISTS home_care_messages (
      id SERIAL PRIMARY KEY,
      request_id INTEGER NOT NULL REFERENCES home_care_requests(id) ON DELETE CASCADE,
      sender_id INTEGER REFERENCES users(id),
      sender_name VARCHAR(160) NOT NULL,
      sender_role VARCHAR(30) NOT NULL,
      body TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS home_care_messages_request_idx ON home_care_messages (request_id, id);
  `);
  await query(`
    ALTER TABLE home_care_requests
      ADD COLUMN IF NOT EXISTS referrer_user_id INTEGER REFERENCES users(id);
  `);
  await query(`
    ALTER TABLE home_care_requests
      ADD COLUMN IF NOT EXISTS patient_id INTEGER REFERENCES patients(id);
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS home_care_requests_referrer_idx ON home_care_requests (referrer_user_id);
  `);
  await query(`
    CREATE INDEX IF NOT EXISTS home_care_requests_patient_idx ON home_care_requests (patient_id);
  `);
  console.log('Home care requests schema ready');
}

/** Case-insensitive town match. No town means no "Near you" label. */
export function homeCareLocationNearTown(location: unknown, town: string | null | undefined): boolean {
  const needle = String(town || '').trim().toLowerCase();
  if (!needle) return false;
  return String(location || '').toLowerCase().includes(needle);
}

function statusRank(status: string): number {
  if (status === 'open') return 0;
  if (status === 'claimed') return 1;
  return 2;
}

function timeValue(value: unknown): number {
  const parsed = new Date(value as string).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

function clip(raw: unknown, max: number): string {
  return String(raw ?? '').trim().slice(0, max);
}

async function loadViewer(userId: number): Promise<Viewer | null> {
  const result = await query(
    `SELECT u.id, u.role, u.name, u.verification_status,
            n.is_active AS nurse_active,
            (n.id IS NOT NULL) AS has_nurse_row,
            n.town AS nurse_town,
            a.name AS agency_name,
            a.town AS agency_town
     FROM users u
     LEFT JOIN nurses n ON n.user_id = u.id
     LEFT JOIN nurse_agencies a ON a.owner_user_id = u.id
     WHERE u.id = $1`,
    [userId]
  );
  const row = result.rows[0];
  if (!row) return null;
  return {
    id: Number(row.id),
    role: String(row.role || ''),
    name: String(row.name || '').trim(),
    verification_status: row.verification_status ? String(row.verification_status) : null,
    nurse_active: row.nurse_active == null ? null : Boolean(row.nurse_active),
    has_nurse_row: Boolean(row.has_nurse_row),
    agency_name: row.agency_name ? String(row.agency_name) : null,
    agency_town: row.agency_town ? String(row.agency_town).trim() : null,
    nurse_town: row.nurse_town ? String(row.nurse_town).trim() : null,
  };
}

function viewerTown(viewer: Viewer): string | null {
  if (viewer.agency_name) return viewer.agency_town || null;
  return viewer.nurse_town || null;
}

function senderRole(viewer: Viewer): 'admin' | 'agency' | 'nurse' {
  if (viewer.role === 'admin') return 'admin';
  if (viewer.agency_name) return 'agency';
  return 'nurse';
}

function senderName(viewer: Viewer): string {
  if (viewer.agency_name) return viewer.agency_name;
  return viewer.name || 'Healynks';
}

/** Approved nurses, approved agency owners, and legacy nurse accounts with no review status. */
function caregiverCanWork(viewer: Viewer): boolean {
  if (viewer.role !== 'nurse') return false;
  const status = (viewer.verification_status || '').toLowerCase();
  if (status === 'pending' || status === 'rejected') return false;
  if (status === 'approved') return true;
  if (viewer.has_nurse_row) return viewer.nurse_active === true;
  return true;
}

function caregiverDeniedMessage(viewer: Viewer | null): string {
  const status = (viewer?.verification_status || '').toLowerCase();
  if (status === 'pending') {
    return 'Your account is still under review, so home care requests are not available yet.';
  }
  if (status === 'rejected') {
    return 'Your account was not approved, so home care requests are not available.';
  }
  return 'You do not have access to home care requests.';
}

/** Pending and rejected accounts cannot refer. A blank status is a legacy clinic doctor. */
function doctorReferralBlocked(viewer: Viewer | null): string | null {
  const status = (viewer?.verification_status || '').toLowerCase();
  if (status === 'pending') {
    return 'Your account is still under review, so you cannot refer a patient to home care yet.';
  }
  if (status === 'rejected') {
    return 'Your account was not approved, so you cannot refer a patient to home care.';
  }
  return null;
}

function readPatientId(body: { patient_id?: unknown; patientId?: unknown }): number | null {
  const raw = body.patient_id ?? body.patientId;
  if (raw == null || raw === '') return null;
  const id = Number(raw);
  if (!Number.isFinite(id) || id <= 0) return null;
  return id;
}

async function doctorCanSeeRequest(userId: number, row: Record<string, unknown>): Promise<boolean> {
  if (row.referrer_user_id != null && Number(row.referrer_user_id) === userId) return true;
  const patientId = row.patient_id == null ? null : Number(row.patient_id);
  if (!patientId) return false;
  const owned = await query(
    `SELECT 1
     WHERE EXISTS (
       SELECT 1 FROM appointments a
       JOIN doctors d ON d.id = a.doctor_id
       WHERE d.user_id = $1 AND a.patient_id = $2
     )
     OR EXISTS (
       SELECT 1 FROM consultations c
       WHERE c.doctor_id = $1 AND c.patient_id = $2
     )`,
    [userId, patientId]
  );
  return Boolean(owned.rows[0]);
}

function claimedLabel(row: Record<string, unknown>): string | null {
  if (row.claimed_by == null) return null;
  const agency = String(row.claimed_agency_name || '').trim();
  if (agency) return agency;
  const name = String(row.claimed_name || '').trim();
  return name || 'A caregiver';
}

function serialize(row: Record<string, unknown>, viewer: { id: number; role: string; town?: string | null }) {
  const status = String(row.status || 'open');
  const claimedBy = row.claimed_by == null ? null : Number(row.claimed_by);
  const mine = claimedBy != null && claimedBy === viewer.id;
  const admin = viewer.role === 'admin';
  const doctor = viewer.role === 'doctor';
  const showPrivate = admin || doctor || status === 'open' || mine;
  const town = admin || doctor ? null : viewer.town ?? null;
  const body: Record<string, unknown> = {
    id: Number(row.id),
    title: row.title,
    status,
    mine,
    taken: status === 'claimed',
    near_you: homeCareLocationNearTown(row.location, town),
    claimed_by_label: claimedLabel(row),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
  if (showPrivate) {
    body.location = row.location;
    body.contact_phone = row.contact_phone;
    body.note = row.note ?? null;
    if (mine || admin || doctor) body.claimed_at = row.claimed_at;
  }
  if (admin || doctor) {
    body.patient_id = row.patient_id == null ? null : Number(row.patient_id);
    body.patient_name = row.patient_name || null;
    const referrerId = row.referrer_user_id == null ? null : Number(row.referrer_user_id);
    body.referrer_user_id = referrerId;
    body.referrer_name = row.referrer_name || null;
    body.referred_by_me = referrerId != null && referrerId === viewer.id;
    body.claimed_by_name = row.claimed_name || null;
    body.claimed_by_agency = row.claimed_agency_name || null;
    body.claimed_at = row.claimed_at;
  }
  if (admin) {
    body.created_by = row.created_by == null ? null : Number(row.created_by);
    body.created_by_name = row.created_by_name || null;
    body.claimed_by = claimedBy;
  }
  return body;
}

async function loadOne(id: number) {
  const result = await query(`${LIST_SQL} WHERE r.id = $1`, [id]);
  return result.rows[0] as Record<string, unknown> | undefined;
}

function presentRows(
  rows: Record<string, unknown>[],
  viewer: { id: number; role: string; town?: string | null }
) {
  const items = rows.map((row) => serialize(row, viewer));
  items.sort((a, b) => {
    const byStatus = statusRank(String(a.status)) - statusRank(String(b.status));
    if (byStatus) return byStatus;
    const near = Number(Boolean(b.near_you)) - Number(Boolean(a.near_you));
    if (near) return near;
    const byTime = timeValue(b.created_at) - timeValue(a.created_at);
    if (byTime) return byTime;
    return Number(b.id) - Number(a.id);
  });
  return items;
}

async function boardViewer(req: AuthedRequest, res: Response): Promise<Viewer | null> {
  const viewer = await loadViewer(req.user!.id);
  if (!viewer) {
    res.status(401).json({ message: 'No token provided' });
    return null;
  }
  if (viewer.role === 'admin') return viewer;
  if (viewer.role !== 'nurse' || !caregiverCanWork(viewer)) {
    res.status(403).json({ message: caregiverDeniedMessage(viewer) });
    return null;
  }
  return viewer;
}

function serializeMessage(row: Record<string, unknown>) {
  return {
    id: Number(row.id),
    request_id: Number(row.request_id),
    sender_id: row.sender_id == null ? null : Number(row.sender_id),
    sender_name: row.sender_name,
    sender_role: row.sender_role,
    body: row.body,
    created_at: row.created_at,
  };
}

function likeTerm(raw: string): string {
  const cleaned = raw.trim().slice(0, 80).replace(/[\\%_]/g, '');
  return `%${cleaned}%`;
}

async function listForDoctor(userId: number, patientId: number | null) {
  const params: unknown[] = [userId];
  let extra = '';
  if (patientId) {
    params.push(patientId);
    extra = ' AND r.patient_id = $2';
  }
  return query(
    `${LIST_SQL}
     WHERE (
       r.referrer_user_id = $1
       OR r.patient_id IN (
         SELECT a.patient_id FROM appointments a
         JOIN doctors d ON d.id = a.doctor_id
         WHERE d.user_id = $1 AND a.patient_id IS NOT NULL
         UNION
         SELECT c.patient_id FROM consultations c
         WHERE c.doctor_id = $1 AND c.patient_id IS NOT NULL
       )
     )${extra}`,
    params
  );
}

export function registerHomeCareRoutes(app: Express) {
  app.post('/api/homecare/requests', authenticate, async (req: AuthedRequest, res: Response) => {
    const role = req.user!.role;
    if (role !== 'admin' && role !== 'doctor') {
      return res.status(403).json({ message: 'You do not have access to home care requests.' });
    }
    const body = req.body;
    if (body == null || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length === 0) {
      return res.status(400).json({ message: 'Title, location, and contact phone are required' });
    }
    const title = clip((body as { title?: unknown }).title, 160);
    const location = clip((body as { location?: unknown }).location, 400);
    const note = clip((body as { note?: unknown }).note, 2000);
    const phoneRaw = (body as { contact_phone?: unknown; contactPhone?: unknown; phone?: unknown }).contact_phone
      ?? (body as { contactPhone?: unknown }).contactPhone
      ?? (body as { phone?: unknown }).phone;
    const phoneText = String(phoneRaw ?? '').trim();
    const phone = normalizeAccountPhone(phoneRaw);
    if (!title || !location || !phoneText) {
      return res.status(400).json({ message: 'Title, location, and contact phone are required' });
    }
    if (!phone) {
      return res.status(400).json({ message: PHONE_INVALID_MESSAGE });
    }

    let viewerRole = role;
    let referrerId: number | null = null;
    let patientId: number | null = null;
    if (role === 'doctor') {
      const viewer = await loadViewer(req.user!.id);
      if (!viewer) return res.status(401).json({ message: 'No token provided' });
      const blocked = doctorReferralBlocked(viewer);
      if (blocked) return res.status(403).json({ message: blocked });
      patientId = readPatientId(body as { patient_id?: unknown; patientId?: unknown });
      if (!patientId) {
        return res.status(400).json({ message: 'Choose the patient this home care request is for.' });
      }
      referrerId = viewer.id;
      viewerRole = 'doctor';
    } else {
      const optional = readPatientId(body as { patient_id?: unknown; patientId?: unknown });
      if (optional) patientId = optional;
    }

    try {
      if (patientId) {
        const patient = await query('SELECT id FROM patients WHERE id = $1', [patientId]);
        if (!patient.rows[0]) {
          return res.status(404).json({ message: 'That patient was not found.' });
        }
      }
      const inserted = await query(
        `INSERT INTO home_care_requests
           (title, location, contact_phone, note, status, created_by, referrer_user_id, patient_id)
         VALUES ($1, $2, $3, $4, 'open', $5, $6, $7)
         RETURNING id`,
        [title, location, phone, note || null, req.user!.id, referrerId, patientId]
      );
      const row = await loadOne(Number(inserted.rows[0].id));
      if (!row) return res.status(500).json({ message: 'Could not post this home care request' });
      return res.status(201).json(serialize(row, { id: req.user!.id, role: viewerRole }));
    } catch (err) {
      console.error('home care create failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not post this home care request' });
    }
  });

  app.get('/api/homecare/patients', authenticate, async (req: AuthedRequest, res: Response) => {
    const role = req.user!.role;
    if (role !== 'doctor' && role !== 'admin') {
      return res.status(403).json({ message: 'You do not have access to home care requests.' });
    }
    try {
      if (role === 'doctor') {
        const viewer = await loadViewer(req.user!.id);
        if (!viewer) return res.status(401).json({ message: 'No token provided' });
        const blocked = doctorReferralBlocked(viewer);
        if (blocked) return res.status(403).json({ message: blocked });
      }
      const q = String(req.query.q || '').trim();
      if (q.length >= 2) {
        const rows = await query(
          `SELECT id, full_name, phone_number
           FROM patients
           WHERE full_name ILIKE $1
              OR phone_number ILIKE $1
              OR COALESCE(patient_code, '') ILIKE $1
           ORDER BY full_name
           LIMIT 15`,
          [likeTerm(q)]
        );
        return res.json({ patients: rows.rows });
      }
      if (role !== 'doctor') return res.json({ patients: [] });
      const rows = await query(
        `SELECT p.id, p.full_name, p.phone_number
         FROM patients p
         WHERE p.id IN (
           SELECT a.patient_id FROM appointments a
           JOIN doctors d ON d.id = a.doctor_id
           WHERE d.user_id = $1 AND a.patient_id IS NOT NULL
           UNION
           SELECT c.patient_id FROM consultations c
           WHERE c.doctor_id = $1 AND c.patient_id IS NOT NULL
         )
         ORDER BY p.full_name
         LIMIT 15`,
        [req.user!.id]
      );
      return res.json({ patients: rows.rows });
    } catch (err) {
      console.error('home care patient search failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not search patients. Try again.' });
    }
  });

  app.get('/api/homecare/requests', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      if (req.user!.role === 'admin') {
        const rows = await query(LIST_SQL);
        return res.json({
          requests: presentRows(rows.rows, { id: req.user!.id, role: 'admin', town: null }),
        });
      }
      if (req.user!.role === 'doctor') {
        const viewer = await loadViewer(req.user!.id);
        if (!viewer) return res.status(401).json({ message: 'No token provided' });
        const blocked = doctorReferralBlocked(viewer);
        if (blocked) return res.status(403).json({ message: blocked });
        const requested = Number(req.query.patient_id);
        const patientId = Number.isFinite(requested) && requested > 0 ? requested : null;
        const rows = await listForDoctor(viewer.id, patientId);
        return res.json({
          requests: presentRows(rows.rows, { id: viewer.id, role: 'doctor', town: null }),
        });
      }
      if (req.user!.role !== 'nurse') {
        return res.status(403).json({ message: 'You do not have access to home care requests.' });
      }
      const viewer = await loadViewer(req.user!.id);
      if (!viewer || !caregiverCanWork(viewer)) {
        return res.status(403).json({ message: caregiverDeniedMessage(viewer) });
      }
      const rows = await query(
        `${LIST_SQL} WHERE r.status IN ('open', 'claimed', 'closed')`
      );
      return res.json({
        requests: presentRows(rows.rows, { id: viewer.id, role: viewer.role, town: viewerTown(viewer) }),
      });
    } catch (err) {
      console.error('home care list failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not load home care requests' });
    }
  });

  app.post('/api/homecare/requests/:id/claim', authenticate, async (req: AuthedRequest, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: 'A valid request id is required' });
    }
    if (req.user!.role !== 'nurse') {
      return res.status(403).json({ message: 'You do not have access to home care requests.' });
    }
    const viewer = await loadViewer(req.user!.id);
    if (!viewer || !caregiverCanWork(viewer)) {
      return res.status(403).json({ message: caregiverDeniedMessage(viewer) });
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const locked = await client.query(
        `SELECT id, status, claimed_by FROM home_care_requests WHERE id = $1 FOR UPDATE`,
        [id]
      );
      const current = locked.rows[0];
      if (!current) {
        await client.query('ROLLBACK');
        return res.status(404).json({ message: 'That home care request was not found' });
      }
      if (String(current.status) !== 'open' || current.claimed_by != null) {
        await client.query('ROLLBACK');
        const closed = String(current.status) === 'closed';
        return res.status(409).json({
          message: closed ? 'This request is closed' : 'This job has been taken.',
        });
      }
      await client.query(
        `UPDATE home_care_requests
         SET status = 'claimed',
             claimed_by = $1,
             claimed_at = CURRENT_TIMESTAMP,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $2`,
        [viewer.id, id]
      );
      await client.query('COMMIT');
    } catch (err) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* already rolling back */
      }
      console.error('home care claim failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not take this home care request' });
    } finally {
      client.release();
    }

    try {
      const row = await loadOne(id);
      if (!row) return res.status(404).json({ message: 'That home care request was not found' });
      return res.status(201).json(serialize(row, { id: viewer.id, role: viewer.role, town: viewerTown(viewer) }));
    } catch (err) {
      console.error('home care claim load failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not take this home care request' });
    }
  });

  app.post('/api/homecare/requests/:id/close', authenticate, async (req: AuthedRequest, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: 'A valid request id is required' });
    }
    const role = req.user!.role;
    if (role !== 'admin' && role !== 'doctor') {
      return res.status(403).json({ message: 'You do not have access to home care requests.' });
    }
    try {
      const viewer = await loadViewer(req.user!.id);
      if (!viewer) return res.status(401).json({ message: 'No token provided' });
      if (viewer.role === 'doctor') {
        const blocked = doctorReferralBlocked(viewer);
        if (blocked) return res.status(403).json({ message: blocked });
      }
      const existing = await loadOne(id);
      if (!existing) return res.status(404).json({ message: 'That home care request was not found' });
      const referrerId = existing.referrer_user_id == null ? null : Number(existing.referrer_user_id);
      const referringDoctor = viewer.role === 'doctor' && referrerId === viewer.id;
      if (viewer.role !== 'admin' && !referringDoctor) {
        return res.status(403).json({
          message: 'Only an admin, or the doctor who referred this patient, can close this request.',
        });
      }
      const updated = await query(
        `UPDATE home_care_requests
         SET status = 'closed', updated_at = CURRENT_TIMESTAMP
         WHERE id = $1
         RETURNING id`,
        [id]
      );
      if (!updated.rows[0]) {
        return res.status(404).json({ message: 'That home care request was not found' });
      }
      const row = await loadOne(id);
      if (!row) return res.status(404).json({ message: 'That home care request was not found' });
      return res.json(serialize(row, { id: viewer.id, role: viewer.role }));
    } catch (err) {
      console.error('home care close failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not close this home care request' });
    }
  });

  app.post('/api/homecare/requests/:id/note', authenticate, async (req: AuthedRequest, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: 'A valid request id is required' });
    }
    const text = clip((req.body as { note?: unknown } | null)?.note, 1000);
    if (!text) return res.status(400).json({ message: 'Write a note first.' });
    const role = req.user!.role;
    if (role !== 'admin' && role !== 'doctor') {
      return res.status(403).json({ message: 'You do not have access to home care requests.' });
    }
    try {
      const viewer = await loadViewer(req.user!.id);
      if (!viewer) return res.status(401).json({ message: 'No token provided' });
      if (viewer.role === 'doctor') {
        const blocked = doctorReferralBlocked(viewer);
        if (blocked) return res.status(403).json({ message: blocked });
      }
      const existing = await loadOne(id);
      if (!existing) return res.status(404).json({ message: 'That home care request was not found' });
      if (viewer.role === 'doctor' && !(await doctorCanSeeRequest(viewer.id, existing))) {
        return res.status(403).json({ message: 'You do not have access to this home care request.' });
      }
      const previous = String(existing.note || '').trim();
      const combined = previous ? `${previous}\n\n${text}` : text;
      if (combined.length > 2000) {
        return res.status(400).json({ message: 'That note is too long. Shorten it and try again.' });
      }
      await query(
        `UPDATE home_care_requests
         SET note = $1, updated_at = CURRENT_TIMESTAMP
         WHERE id = $2`,
        [combined, id]
      );
      const row = await loadOne(id);
      if (!row) return res.status(404).json({ message: 'That home care request was not found' });
      return res.json(serialize(row, { id: viewer.id, role: viewer.role }));
    } catch (err) {
      console.error('home care note failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not add that note. Try again.' });
    }
  });

  app.get('/api/homecare/requests/:id/messages', authenticate, async (req: AuthedRequest, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: 'A valid request id is required' });
    }
    try {
      const viewer = await boardViewer(req, res);
      if (!viewer) return;
      const request = await loadOne(id);
      if (!request) return res.status(404).json({ message: 'That home care request was not found' });
      const rows = await query(
        `SELECT id, request_id, sender_id, sender_name, sender_role, body, created_at
         FROM home_care_messages
         WHERE request_id = $1
         ORDER BY id ASC`,
        [id]
      );
      return res.json({ messages: rows.rows.map((row) => serializeMessage(row)) });
    } catch (err) {
      console.error('home care messages list failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not load messages. Try again.' });
    }
  });

  app.post('/api/homecare/requests/:id/messages', authenticate, async (req: AuthedRequest, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: 'A valid request id is required' });
    }
    const text = clip((req.body as { body?: unknown } | null)?.body, 2000);
    if (!text) return res.status(400).json({ message: 'Write a message first.' });
    try {
      const viewer = await boardViewer(req, res);
      if (!viewer) return;
      const request = await loadOne(id);
      if (!request) return res.status(404).json({ message: 'That home care request was not found' });
      const inserted = await query(
        `INSERT INTO home_care_messages (request_id, sender_id, sender_name, sender_role, body)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, request_id, sender_id, sender_name, sender_role, body, created_at`,
        [id, viewer.id, senderName(viewer), senderRole(viewer), text]
      );
      return res.status(201).json(serializeMessage(inserted.rows[0]));
    } catch (err) {
      console.error('home care message send failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not send that message. Try again.' });
    }
  });
}
