import crypto from 'crypto';
import type { Express, Response } from 'express';
import { pool, query } from './db';
import { authenticate, authenticateOptional, type AuthedRequest } from './authz';
import { normalizeAccountPhone, PHONE_INVALID_MESSAGE } from './professional_signup';
import { sendSMS } from './sms';
import {
  homeCareJobUrl,
  isHomeCareShareToken,
  newHomeCareShareToken,
  notifyApprovedNursesOfHomeCare,
  type HomeCareNurseCandidate,
  type HomeCarePushSender,
} from './homecare_notify';
import {
  HOME_CARE_STAY_IN_LINE,
  homeCareShowsStayIn,
  homeCareUpdateStatement,
  normalizeCustomOption,
  normalizeHomeCareOptions,
} from './homecare_options';

/**
 * Home-care request board.
 * Admins and doctors post a visit. Approved nurses and nurse-agency owners claim it.
 * A successful create texts each approved nurse once and writes one in-app notification.
 * Claim, close, chat, and edits do not notify again.
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
  await query(`
    ALTER TABLE home_care_requests
      ADD COLUMN IF NOT EXISTS care_options TEXT[] NOT NULL DEFAULT '{}';
  `);
  await query(`
    ALTER TABLE home_care_requests
      ADD COLUMN IF NOT EXISTS custom_option VARCHAR(80);
  `);
  await ensureHomeCareShareTokens();
  console.log('Home care requests schema ready');
}

function isShareTokenConflict(err: unknown): boolean {
  const code = (err as { code?: string }).code;
  const constraint = String((err as { constraint?: string }).constraint || '');
  return code === '23505' && (constraint === '' || constraint.includes('share_token'));
}

/** Adds an unguessable share token. Existing rows are filled in without sending SMS. */
async function ensureHomeCareShareTokens() {
  await query(`
    ALTER TABLE home_care_requests
      ADD COLUMN IF NOT EXISTS share_token VARCHAR(128);
  `);
  const missing = await query(
    `SELECT id FROM home_care_requests WHERE share_token IS NULL OR BTRIM(share_token) = ''`
  );
  for (const row of missing.rows) {
    for (let attempt = 0; attempt < 4; attempt++) {
      try {
        await query(
          `UPDATE home_care_requests
           SET share_token = $1
           WHERE id = $2 AND (share_token IS NULL OR BTRIM(share_token) = '')`,
          [newHomeCareShareToken(), row.id]
        );
        break;
      } catch (err) {
        if (!isShareTokenConflict(err) || attempt === 3) throw err;
      }
    }
  }
  await query(`
    CREATE UNIQUE INDEX IF NOT EXISTS home_care_requests_share_token_idx
    ON home_care_requests (share_token);
  `);
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

function readOptionPayload(body: Record<string, unknown>) {
  const optionsProvided = 'care_options' in body || 'careOptions' in body;
  const customProvided = 'custom_option' in body || 'customOption' in body;
  return {
    optionsProvided,
    customProvided,
    options: normalizeHomeCareOptions(optionsProvided ? (body.care_options ?? body.careOptions) : []),
    custom: customProvided ? normalizeCustomOption(body.custom_option ?? body.customOption) : null,
  };
}

function phoneFromBody(body: Record<string, unknown>): { present: boolean; raw: unknown; text: string } {
  const key = (['contact_phone', 'contactPhone', 'phone'] as const).find((name) => name in body);
  if (!key) return { present: false, raw: undefined, text: '' };
  const raw = body[key];
  return { present: true, raw, text: String(raw ?? '').trim() };
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
  const createdBy = row.created_by == null ? null : Number(row.created_by);
  const body: Record<string, unknown> = {
    id: Number(row.id),
    title: row.title,
    status,
    mine,
    taken: status === 'claimed',
    // Display hint only. The stored status stays "open" until someone claims it.
    posted_by_me: createdBy != null && createdBy === viewer.id,
    near_you: homeCareLocationNearTown(row.location, town),
    claimed_by_label: claimedLabel(row),
    created_at: row.created_at,
    updated_at: row.updated_at,
    care_options: normalizeHomeCareOptions(row.care_options),
    custom_option: normalizeCustomOption(row.custom_option),
    stay_in_note: homeCareShowsStayIn(
      normalizeHomeCareOptions(row.care_options),
      normalizeCustomOption(row.custom_option)
    )
      ? HOME_CARE_STAY_IN_LINE
      : null,
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
    body.created_by = createdBy;
    body.created_by_name = row.created_by_name || null;
    body.claimed_by = claimedBy;
  }
  const shareToken = String(row.share_token || '').trim();
  const referrerForShare = row.referrer_user_id == null ? null : Number(row.referrer_user_id);
  const mayCopyLink = admin || (doctor && referrerForShare === viewer.id);
  if (mayCopyLink && isHomeCareShareToken(shareToken)) {
    body.share_token = shareToken;
    body.share_url = homeCareJobUrl(shareToken);
  }
  return body;
}

function publicStatus(raw: unknown): 'open' | 'claimed' | 'closed' {
  const status = String(raw || 'open');
  if (status === 'open' || status === 'claimed' || status === 'closed') return status;
  return 'closed';
}

/** Logged-out share view. No phone, note, patient, creator, or token echo. */
export function publicHomeCareShare(row: Record<string, unknown>) {
  const status = publicStatus(row.status);
  const careOptions = normalizeHomeCareOptions(row.care_options);
  const customOption = normalizeCustomOption(row.custom_option);
  return {
    title: String(row.title || 'Home care').slice(0, 160),
    location: String(row.location || '').slice(0, 400),
    status,
    taken: status === 'claimed',
    care_options: careOptions,
    custom_option: customOption,
    stay_in_note: homeCareShowsStayIn(careOptions, customOption) ? HOME_CARE_STAY_IN_LINE : null,
  };
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

async function loadApprovedHomeCareNurses(): Promise<HomeCareNurseCandidate[]> {
  const result = await query(
    `SELECT u.id,
            u.role,
            NULLIF(BTRIM(u.phone_number), '') AS phone,
            u.verification_status,
            BOOL_OR(COALESCE(n.is_active, FALSE)) AS is_active
     FROM users u
     LEFT JOIN nurses n ON n.user_id = u.id
     WHERE u.role = 'nurse'
       AND LOWER(BTRIM(COALESCE(u.verification_status, ''))) NOT IN ('pending', 'rejected')
     GROUP BY u.id, u.role, u.phone_number, u.verification_status
     HAVING LOWER(BTRIM(COALESCE(u.verification_status, ''))) = 'approved'
         OR BOOL_OR(COALESCE(n.is_active, FALSE)) = TRUE`
  );
  return result.rows.map((row) => ({
    id: Number(row.id),
    role: String(row.role || ''),
    phone: row.phone ? String(row.phone) : null,
    verification_status: row.verification_status ? String(row.verification_status) : null,
    is_active: row.is_active === true || row.is_active === 't' || row.is_active === 'true',
  }));
}

async function insertOpenHomeCareRequest(input: {
  title: string;
  location: string;
  phone: string;
  note: string | null;
  createdBy: number;
  referrerId: number | null;
  patientId: number | null;
  careOptions: string[];
  customOption: string | null;
}): Promise<{ id: number; token: string }> {
  let last: unknown;
  for (let attempt = 0; attempt < 4; attempt++) {
    const token = newHomeCareShareToken();
    try {
      const inserted = await query(
        `INSERT INTO home_care_requests
           (title, location, contact_phone, note, status, created_by, referrer_user_id, patient_id, share_token, care_options, custom_option)
         VALUES ($1, $2, $3, $4, 'open', $5, $6, $7, $8, $9, $10)
         RETURNING id, share_token`,
        [
          input.title,
          input.location,
          input.phone,
          input.note,
          input.createdBy,
          input.referrerId,
          input.patientId,
          token,
          input.careOptions,
          input.customOption,
        ]
      );
      return {
        id: Number(inserted.rows[0].id),
        token: String(inserted.rows[0].share_token || token),
      };
    } catch (err) {
      last = err;
      if (!isShareTokenConflict(err) || attempt === 3) throw err;
    }
  }
  throw last instanceof Error ? last : new Error('Could not post this home care request');
}

/** Runs after the request row is stored. One failure does not cancel the post or the other nurses. */
function queueHomeCareNurseAlerts(
  job: { title: string; location: string; token: string },
  sendPush?: HomeCarePushSender
) {
  const token = String(job.token || '').trim();
  if (!isHomeCareShareToken(token)) {
    console.error('home care alert skipped, share token missing');
    return;
  }
  void deliverHomeCareNurseAlerts({ ...job, token }, sendPush).catch((err) => {
    console.error('home care nurse alerts failed', err instanceof Error ? err.message : 'error');
  });
}

async function deliverHomeCareNurseAlerts(
  job: { title: string; location: string; token: string },
  sendPush?: HomeCarePushSender
) {
  const nurses = await loadApprovedHomeCareNurses();
  const summary = await notifyApprovedNursesOfHomeCare({
    nurses,
    title: job.title,
    location: job.location,
    token: job.token,
    sendSMS,
    sendPush,
    writeNotification: async (userId, title, message) => {
      await query(
        `INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, 'homecare')`,
        [userId, title, message]
      );
    },
  });
  console.log(
    `[HOME CARE] Alerts for ${homeCareJobUrl(job.token)}: ${summary.inApp} in-app, ${summary.sms} sms, ${summary.skippedNoPhone} without a phone`
  );
}

export function registerHomeCareRoutes(
  app: Express,
  deps: { sendPushNotification?: HomeCarePushSender } = {}
) {
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
      const careOptions = normalizeHomeCareOptions(
        (body as { care_options?: unknown; careOptions?: unknown }).care_options
          ?? (body as { careOptions?: unknown }).careOptions
      );
      const customOption = normalizeCustomOption(
        (body as { custom_option?: unknown; customOption?: unknown }).custom_option
          ?? (body as { customOption?: unknown }).customOption
      );
      const created = await insertOpenHomeCareRequest({
        title,
        location,
        phone,
        note: note || null,
        createdBy: req.user!.id,
        referrerId,
        patientId,
        careOptions,
        customOption,
      });
      const row = await loadOne(created.id);
      if (!row) return res.status(500).json({ message: 'Could not post this home care request' });
      queueHomeCareNurseAlerts(
        {
          title: String(row.title || title),
          location: String(row.location || location),
          token: String(row.share_token || created.token),
        },
        deps.sendPushNotification
      );
      return res.status(201).json(serialize(row, { id: req.user!.id, role: viewerRole }));
    } catch (err) {
      console.error('home care create failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not post this home care request' });
    }
  });

  app.get('/api/homecare/share/:token', authenticateOptional, async (req: AuthedRequest, res: Response) => {
    const raw = req.params.token;
    const token = Array.isArray(raw) ? String(raw[0] || '') : String(raw || '');
    if (!isHomeCareShareToken(token)) {
      return res.status(404).json({ message: 'That home care request was not found' });
    }
    try {
      const result = await query(`${LIST_SQL} WHERE r.share_token = $1`, [token]);
      const row = result.rows[0] as Record<string, unknown> | undefined;
      if (!row) return res.status(404).json({ message: 'That home care request was not found' });
      if (!req.user) return res.json(publicHomeCareShare(row));

      const viewer = await loadViewer(req.user.id);
      if (!viewer) return res.json(publicHomeCareShare(row));

      if (viewer.role === 'admin') {
        return res.json(serialize(row, { id: viewer.id, role: 'admin', town: null }));
      }

      if (viewer.role === 'doctor') {
        const referrerId = row.referrer_user_id == null ? null : Number(row.referrer_user_id);
        if (referrerId === viewer.id) {
          return res.json(serialize(row, { id: viewer.id, role: 'doctor', town: null }));
        }
        return res.json(publicHomeCareShare(row));
      }

      if (viewer.role === 'nurse') {
        const review = (viewer.verification_status || '').toLowerCase();
        if (review === 'pending') {
          return res.json({ ...publicHomeCareShare(row), pending_review: true });
        }
        if (!caregiverCanWork(viewer)) return res.json(publicHomeCareShare(row));
        return res.json(
          serialize(row, { id: viewer.id, role: viewer.role, town: viewerTown(viewer) })
        );
      }

      return res.json(publicHomeCareShare(row));
    } catch (err) {
      console.error('home care share lookup failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not open this home care request' });
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

  // Edits update the same row. They do not call queueHomeCareNurseAlerts or sendSMS.
  app.patch('/api/homecare/requests/:id', authenticate, async (req: AuthedRequest, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ message: 'A valid request id is required' });
    }
    const role = req.user!.role;
    if (role !== 'admin' && role !== 'doctor') {
      return res.status(403).json({ message: 'You do not have access to home care requests.' });
    }
    const body = req.body;
    if (body == null || typeof body !== 'object' || Array.isArray(body)) {
      return res.status(400).json({ message: 'Title, location, and contact phone are required' });
    }
    const record = body as Record<string, unknown>;
    const titlePresent = 'title' in record;
    const locationPresent = 'location' in record;
    const title = clip(record.title, 160);
    const location = clip(record.location, 400);
    const phoneField = phoneFromBody(record);
    if (!titlePresent || !title || !locationPresent || !location || !phoneField.present || !phoneField.text) {
      return res.status(400).json({ message: 'Title, location, and contact phone are required' });
    }
    const phone = normalizeAccountPhone(phoneField.raw);
    if (!phone) {
      return res.status(400).json({ message: PHONE_INVALID_MESSAGE });
    }
    const care = readOptionPayload(record);
    const noteProvided = 'note' in record;
    const note = noteProvided ? clip(record.note, 2000) : '';

    try {
      const viewer = await loadViewer(req.user!.id);
      if (!viewer) return res.status(401).json({ message: 'No token provided' });
      if (viewer.role === 'doctor') {
        const blocked = doctorReferralBlocked(viewer);
        if (blocked) return res.status(403).json({ message: blocked });
      }
      const existing = await loadOne(id);
      if (!existing) return res.status(404).json({ message: 'That home care request was not found' });
      const open = String(existing.status) === 'open' && existing.claimed_by == null;
      const referrerId = existing.referrer_user_id == null ? null : Number(existing.referrer_user_id);
      const referringDoctor = viewer.role === 'doctor' && referrerId === viewer.id;
      if (viewer.role !== 'admin' && !referringDoctor) {
        return res.status(403).json({
          message: 'Only an admin, or the doctor who referred this patient, can edit this request.',
        });
      }
      if (!open && viewer.role !== 'admin') {
        return res.status(403).json({
          message: 'You can edit this request while it is still open.',
        });
      }

      const nextNote = noteProvided
        ? (note || null)
        : (existing.note == null ? null : String(existing.note));
      const nextOptions = care.optionsProvided
        ? care.options
        : normalizeHomeCareOptions(existing.care_options);
      const nextCustom = care.customProvided
        ? care.custom
        : normalizeCustomOption(existing.custom_option);

      const updated = open
        ? await query(homeCareUpdateStatement(true), [
            title,
            location,
            phone,
            nextNote,
            nextOptions,
            nextCustom,
            id,
          ])
        : await query(homeCareUpdateStatement(false), [phone, nextNote, id]);
      if (!updated.rows[0]) {
        const again = await loadOne(id);
        if (!again) return res.status(404).json({ message: 'That home care request was not found' });
        const closed = String(again.status) === 'closed';
        return res.status(409).json({
          message: closed ? 'This request is closed' : 'This job has been taken.',
        });
      }
      const row = await loadOne(id);
      if (!row) return res.status(404).json({ message: 'That home care request was not found' });
      return res.json(serialize(row, { id: viewer.id, role: viewer.role, town: viewerTown(viewer) }));
    } catch (err) {
      console.error('home care edit failed', (err as { code?: string })?.code || 'error');
      return res.status(500).json({ message: 'Could not save this home care request' });
    }
  });
}
