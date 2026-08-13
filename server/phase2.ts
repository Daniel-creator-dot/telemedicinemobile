import type { Express, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import { query } from './db';
import { haversineKm, regionCentroid } from './phase5';
import { getAccessiblePatientIds, getPatientForUser } from './patients';

type AuthedRequest = Request & { user?: { id: number; username: string; role: string } };

type Deps = {
  authenticate: (req: AuthedRequest, res: Response, next: NextFunction) => void;
  sendSMS: (recipient: string, message: string) => Promise<void>;
  sendPushNotification: (
    userIds: number[],
    title: string,
    body: string,
    data?: Record<string, string>
  ) => Promise<void>;
};

const PARTNER_TYPES = ['pharmacy', 'laboratory', 'imaging', 'hospital'] as const;

export async function initPhase2Schema() {
  await query(`CREATE SEQUENCE IF NOT EXISTS referral_code_seq START 200001`);

  await query(`
    CREATE TABLE IF NOT EXISTS partner_orgs (
      id SERIAL PRIMARY KEY,
      name VARCHAR(160) NOT NULL,
      type VARCHAR(30) NOT NULL,
      region VARCHAR(80),
      town VARCHAR(80),
      address TEXT,
      phone VARCHAR(20),
      is_active BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS partner_staff (
      id SERIAL PRIMARY KEY,
      org_id INTEGER REFERENCES partner_orgs(id) ON DELETE CASCADE,
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE(org_id, user_id)
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS referrals (
      id SERIAL PRIMARY KEY,
      referral_code VARCHAR(30) UNIQUE,
      appointment_id INTEGER REFERENCES appointments(id),
      patient_id INTEGER REFERENCES patients(id),
      from_doctor_id INTEGER REFERENCES users(id),
      to_doctor_id INTEGER REFERENCES users(id),
      to_org_id INTEGER REFERENCES partner_orgs(id),
      specialty VARCHAR(100),
      reason TEXT,
      clinical_summary TEXT,
      urgency VARCHAR(20) DEFAULT 'routine',
      status VARCHAR(20) DEFAULT 'pending',
      result_notes TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      accepted_at TIMESTAMP,
      completed_at TIMESTAMP
    );
  `);

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='pharmacy_id') THEN
        ALTER TABLE prescriptions ADD COLUMN pharmacy_id INTEGER REFERENCES partner_orgs(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='dispense_status') THEN
        ALTER TABLE prescriptions ADD COLUMN dispense_status VARCHAR(20) DEFAULT 'unsent';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='dispensed_at') THEN
        ALTER TABLE prescriptions ADD COLUMN dispensed_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='dispensed_by') THEN
        ALTER TABLE prescriptions ADD COLUMN dispensed_by VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='pharmacy_notes') THEN
        ALTER TABLE prescriptions ADD COLUMN pharmacy_notes TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='lab_requests' AND column_name='partner_id') THEN
        ALTER TABLE lab_requests ADD COLUMN partner_id INTEGER REFERENCES partner_orgs(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='lab_requests' AND column_name='result_returned_at') THEN
        ALTER TABLE lab_requests ADD COLUMN result_returned_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scan_requests' AND column_name='partner_id') THEN
        ALTER TABLE scan_requests ADD COLUMN partner_id INTEGER REFERENCES partner_orgs(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scan_requests' AND column_name='result_returned_at') THEN
        ALTER TABLE scan_requests ADD COLUMN result_returned_at TIMESTAMP;
      END IF;
    END $$;
  `);

  await seedPartnersAndStaff();
  console.log('Phase 2 schema ready');
}

async function seedPartnersAndStaff() {
  const existing = await query('SELECT COUNT(*) FROM partner_orgs');
  if (parseInt(existing.rows[0].count, 10) === 0) {
    await query(`
      INSERT INTO partner_orgs (name, type, region, town, address, phone) VALUES
        ('Accra Central Pharmacy', 'pharmacy', 'Greater Accra', 'Accra', 'Kojo Thompson Rd, Accra', '0302001001'),
        ('Kumasi Community Pharmacy', 'pharmacy', 'Ashanti', 'Kumasi', 'Kejetia Market, Kumasi', '0322001002'),
        ('Korle-Bu Diagnostic Lab', 'laboratory', 'Greater Accra', 'Accra', 'Korle-Bu Teaching Hospital', '0302002001'),
        ('Ridge Imaging Centre', 'imaging', 'Greater Accra', 'Accra', 'Ridge Hospital Road, Accra', '0302003001'),
        ('Tamale Regional Hospital', 'hospital', 'Northern', 'Tamale', 'Hospital Road, Tamale', '0372004001')
    `);
    console.log('Seeded Digi Health partner network');
  }

  await ensurePartnerUser('pharmacy', 'pharm123', 'pharmacy', 'Ama Boateng', '0240000101', 'Accra Central Pharmacy');
  await ensurePartnerUser('imaging', 'image123', 'imaging', 'Kojo Asante', '0240000102', 'Ridge Imaging Centre');

  const labtech = await query("SELECT id FROM users WHERE username = 'labtech' LIMIT 1");
  const labOrg = await query("SELECT id FROM partner_orgs WHERE name = 'Korle-Bu Diagnostic Lab' LIMIT 1");
  if (labtech.rows[0] && labOrg.rows[0]) {
    await query(
      'INSERT INTO partner_staff (org_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [labOrg.rows[0].id, labtech.rows[0].id]
    );
  }
}

async function ensurePartnerUser(
  username: string,
  password: string,
  role: string,
  name: string,
  phone: string,
  orgName: string
) {
  let user = await query('SELECT id FROM users WHERE username = $1', [username]);
  if (!user.rows[0]) {
    const hashed = await bcrypt.hash(password, 10);
    user = await query(
      'INSERT INTO users (username, password, role, name, phone_number) VALUES ($1, $2, $3, $4, $5) RETURNING id',
      [username, hashed, role, name, phone]
    );
    console.log(`Default ${role} user created (${username}/${password})`);
  }
  const org = await query('SELECT id FROM partner_orgs WHERE name = $1 LIMIT 1', [orgName]);
  if (org.rows[0] && user.rows[0]) {
    await query(
      'INSERT INTO partner_staff (org_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
      [org.rows[0].id, user.rows[0].id]
    );
  }
}

function scoreLocation(patient: { region?: string; town?: string }, partner: { region?: string; town?: string }) {
  const pRegion = (patient.region || '').trim().toLowerCase();
  const pTown = (patient.town || '').trim().toLowerCase();
  const oRegion = (partner.region || '').trim().toLowerCase();
  const oTown = (partner.town || '').trim().toLowerCase();
  let score = 0;
  if (pTown && oTown && pTown === oTown) score += 2;
  if (pRegion && oRegion && pRegion === oRegion) score += 1;
  return score;
}

export async function assignNearestPartner(kind: 'laboratory' | 'imaging' | 'pharmacy', patientId: number | null) {
  if (!patientId) return null;
  const patient = await query('SELECT region, town, preferred_location FROM patients WHERE id = $1', [patientId]);
  const partners = await query(
    'SELECT * FROM partner_orgs WHERE type = $1 AND is_active = TRUE',
    [kind]
  );
  if (!patient.rows[0] || partners.rows.length === 0) return null;

  const loc = {
    region: patient.rows[0].region || patient.rows[0].preferred_location,
    town: patient.rows[0].town,
  };
  const origin = regionCentroid(loc.region || loc.town);
  const ranked = partners.rows
    .map((p: any) => {
      let distance = 9999;
      if (origin && p.lat != null && p.lng != null) {
        distance = haversineKm(origin, { lat: Number(p.lat), lng: Number(p.lng) });
      }
      return { p, score: scoreLocation(loc, p), distance };
    })
    .sort((a: any, b: any) => b.score - a.score || a.distance - b.distance);
  return ranked[0]?.p ?? null;
}

async function notifyUser(
  deps: Pick<Deps, 'sendPushNotification'>,
  userId: number | null | undefined,
  title: string,
  message: string,
  type = 'network'
) {
  if (!userId) return;
  await query(
    'INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, $4)',
    [userId, title, message, type]
  );
  await deps.sendPushNotification([userId], title, message, { type });
}

async function patientUserId(patientId: number | null | undefined) {
  if (!patientId) return null;
  const r = await query('SELECT user_id, phone_number FROM patients WHERE id = $1', [patientId]);
  return r.rows[0] || null;
}

export async function notifyDiagnosticClosedLoop(
  deps: Pick<Deps, 'sendSMS' | 'sendPushNotification'>,
  row: { patient_id?: number; doctor_id?: number; test_name?: string; scan_type?: string; results?: string },
  kind: 'lab' | 'scan'
) {
  const label = kind === 'lab' ? row.test_name || 'Lab test' : row.scan_type || 'Scan';
  const title = `${label} result ready`;
  const body = row.results ? `${label}: ${String(row.results).slice(0, 140)}` : `${label} results have been returned.`;
  const patient = await patientUserId(row.patient_id);
  if (patient?.user_id) await notifyUser(deps, patient.user_id, title, body, 'result');
  if (patient?.phone_number) {
    await deps.sendSMS(patient.phone_number, `Digi Health: ${body}`);
  }
  if (row.doctor_id) await notifyUser(deps, row.doctor_id, title, `Result returned for your patient. ${body}`, 'result');
}

async function orgForUser(userId: number) {
  const r = await query(
    `SELECT o.* FROM partner_orgs o
     JOIN partner_staff s ON s.org_id = o.id
     WHERE s.user_id = $1
     LIMIT 1`,
    [userId]
  );
  return r.rows[0] || null;
}

function nextReferralCode(n: number) {
  return `REF-${String(n).padStart(6, '0')}`;
}

export function registerPhase2Routes(app: Express, deps: Deps) {
  const { authenticate } = deps;

  app.get('/api/partners', authenticate, async (req: AuthedRequest, res) => {
    try {
      const type = String(req.query.type || '');
      const region = String(req.query.region || '');
      const params: any[] = [];
      const where: string[] = ['is_active = TRUE'];
      if (type && PARTNER_TYPES.includes(type as any)) {
        params.push(type);
        where.push(`type = $${params.length}`);
      }
      if (region) {
        params.push(region);
        where.push(`region ILIKE $${params.length}`);
      }
      const result = await query(
        `SELECT * FROM partner_orgs WHERE ${where.join(' AND ')} ORDER BY name`,
        params
      );
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/partners/nearby', authenticate, async (req: AuthedRequest, res) => {
    try {
      const type = String(req.query.type || 'pharmacy');
      const patientId = req.query.patient_id ? Number(req.query.patient_id) : null;
      const partners = await query(
        'SELECT * FROM partner_orgs WHERE type = $1 AND is_active = TRUE',
        [type]
      );
      let loc = { region: '', town: '' };
      if (patientId) {
        const p = await query('SELECT region, town, preferred_location FROM patients WHERE id = $1', [patientId]);
        loc = {
          region: p.rows[0]?.region || p.rows[0]?.preferred_location || '',
          town: p.rows[0]?.town || '',
        };
      }
      const ranked = partners.rows
        .map((p: any) => ({ ...p, match_score: scoreLocation(loc, p) }))
        .sort((a: any, b: any) => b.match_score - a.match_score);
      res.json(ranked);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/partners/me', authenticate, async (req: AuthedRequest, res) => {
    try {
      const org = await orgForUser(req.user!.id);
      res.json(org || null);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/prescriptions/:id/send', authenticate, async (req: AuthedRequest, res) => {
    if (!['doctor', 'admin', 'nurse'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const rx = await query('SELECT * FROM prescriptions WHERE id = $1', [req.params.id]);
      if (!rx.rows[0]) return res.status(404).json({ message: 'Prescription not found' });

      let pharmacyId = req.body.pharmacy_id ? Number(req.body.pharmacy_id) : null;
      if (!pharmacyId) {
        const nearest = await assignNearestPartner('pharmacy', rx.rows[0].patient_id);
        pharmacyId = nearest?.id || null;
      }
      if (!pharmacyId) return res.status(400).json({ message: 'No pharmacy available on the network' });

      const result = await query(
        `UPDATE prescriptions
         SET pharmacy_id = $1, dispense_status = 'sent'
         WHERE id = $2 RETURNING *`,
        [pharmacyId, req.params.id]
      );
      const org = await query('SELECT name, phone FROM partner_orgs WHERE id = $1', [pharmacyId]);
      const patient = await patientUserId(rx.rows[0].patient_id);
      const pharmacyName = org.rows[0]?.name || 'a network pharmacy';
      if (patient?.user_id) {
        await notifyUser(
          deps,
          patient.user_id,
          'Prescription sent to pharmacy',
          `${rx.rows[0].medication_name} was sent to ${pharmacyName}.`,
          'pharmacy'
        );
      }
      if (patient?.phone_number) {
        await deps.sendSMS(
          patient.phone_number,
          `Digi Health: Your prescription ${rx.rows[0].prescription_ref || ''} was sent to ${pharmacyName}.`
        );
      }
      const staff = await query('SELECT user_id FROM partner_staff WHERE org_id = $1', [pharmacyId]);
      for (const s of staff.rows) {
        await notifyUser(deps, s.user_id, 'New e-prescription', `${rx.rows[0].medication_name} ready to dispense.`, 'pharmacy');
      }
      res.json({ ...result.rows[0], pharmacy_name: pharmacyName });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/pharmacy/queue', authenticate, async (req: AuthedRequest, res) => {
    if (!['pharmacy', 'admin', 'medical_ops'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const org = await orgForUser(req.user!.id);
      const params: any[] = [];
      let where = `pr.dispense_status IN ('sent','received','preparing','ready','dispensed')`;
      if (org && req.user!.role === 'pharmacy') {
        params.push(org.id);
        where += ` AND pr.pharmacy_id = $${params.length}`;
      }
      const result = await query(
        `SELECT pr.*, a.appointment_id as apt_code, p.full_name as patient_name, p.phone_number as patient_phone,
                p.patient_code, o.name as pharmacy_name
         FROM prescriptions pr
         JOIN patients p ON pr.patient_id = p.id
         JOIN appointments a ON pr.appointment_id = a.id
         LEFT JOIN partner_orgs o ON pr.pharmacy_id = o.id
         WHERE ${where}
         ORDER BY pr.created_at DESC`,
        params
      );
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/pharmacy/prescriptions/:id', authenticate, async (req: AuthedRequest, res) => {
    if (!['pharmacy', 'admin'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const { status, notes } = req.body;
      const allowed = ['received', 'preparing', 'ready', 'dispensed', 'unavailable'];
      if (!allowed.includes(status)) return res.status(400).json({ message: 'Invalid status' });

      const user = await query('SELECT name FROM users WHERE id = $1', [req.user!.id]);
      const result = await query(
        `UPDATE prescriptions
         SET dispense_status = $1,
             pharmacy_notes = COALESCE($2, pharmacy_notes),
             dispensed_by = $3,
             dispensed_at = CASE WHEN $1 = 'dispensed' THEN CURRENT_TIMESTAMP ELSE dispensed_at END
         WHERE id = $4 RETURNING *`,
        [status, notes || null, user.rows[0]?.name || req.user!.username, req.params.id]
      );
      if (!result.rows[0]) return res.status(404).json({ message: 'Not found' });

      const patient = await patientUserId(result.rows[0].patient_id);
      const labels: Record<string, string> = {
        received: 'Pharmacy received your prescription',
        preparing: 'Pharmacy is preparing your medication',
        ready: 'Your medication is ready for pickup',
        dispensed: 'Your medication has been dispensed',
        unavailable: 'Pharmacy could not fill this prescription',
      };
      const title = labels[status];
      if (patient?.user_id) await notifyUser(deps, patient.user_id, title, result.rows[0].medication_name, 'pharmacy');
      if (patient?.phone_number && (status === 'ready' || status === 'dispensed')) {
        await deps.sendSMS(patient.phone_number, `Digi Health: ${title} — ${result.rows[0].medication_name}`);
      }
      res.json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/referrals', authenticate, async (req: AuthedRequest, res) => {
    if (!['doctor', 'admin'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const {
        appointment_id,
        patient_id,
        to_doctor_id,
        to_org_id,
        specialty,
        reason,
        clinical_summary,
        urgency,
      } = req.body;
      if (!patient_id || !reason) return res.status(400).json({ message: 'Patient and reason are required' });

      const seq = await query(`SELECT nextval('referral_code_seq') AS n`);
      const code = nextReferralCode(seq.rows[0].n);
      const result = await query(
        `INSERT INTO referrals (
           referral_code, appointment_id, patient_id, from_doctor_id, to_doctor_id, to_org_id,
           specialty, reason, clinical_summary, urgency, status
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'pending') RETURNING *`,
        [
          code,
          appointment_id || null,
          patient_id,
          req.user!.id,
          to_doctor_id || null,
          to_org_id || null,
          specialty || null,
          reason,
          clinical_summary || null,
          urgency || 'routine',
        ]
      );
      const row = result.rows[0];
      if (to_doctor_id) {
        await notifyUser(deps, to_doctor_id, 'New specialist referral', `${code}: ${reason}`, 'referral');
      }
      const patient = await patientUserId(patient_id);
      if (patient?.user_id) {
        await notifyUser(deps, patient.user_id, 'Specialist referral created', `${code} — ${specialty || 'specialist'}`, 'referral');
      }
      res.status(201).json(row);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/referrals', authenticate, async (req: AuthedRequest, res) => {
    try {
      const role = req.user!.role;
      const params: any[] = [];
      let where = 'TRUE';
      if (role === 'doctor') {
        params.push(req.user!.id);
        where = `(r.from_doctor_id = $${params.length} OR r.to_doctor_id = $${params.length})`;
      } else if (role === 'patient') {
        const patient = await query('SELECT id FROM patients WHERE user_id = $1', [req.user!.id]);
        if (!patient.rows[0]) return res.json([]);
        params.push(patient.rows[0].id);
        where = `r.patient_id = $${params.length}`;
      } else if (!['admin', 'medical_ops', 'nurse'].includes(role)) {
        return res.status(403).json({ message: 'Forbidden' });
      }

      const result = await query(
        `SELECT r.*, p.full_name as patient_name, p.patient_code,
                fd.name as from_doctor_name, td.name as to_doctor_name, o.name as org_name
         FROM referrals r
         JOIN patients p ON r.patient_id = p.id
         LEFT JOIN users fd ON r.from_doctor_id = fd.id
         LEFT JOIN users td ON r.to_doctor_id = td.id
         LEFT JOIN partner_orgs o ON r.to_org_id = o.id
         WHERE ${where}
         ORDER BY r.created_at DESC`,
        params
      );
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/referrals/:id', authenticate, async (req: AuthedRequest, res) => {
    if (!['doctor', 'admin', 'medical_ops'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const { status, result_notes, to_doctor_id } = req.body;
      const existing = await query('SELECT * FROM referrals WHERE id = $1', [req.params.id]);
      if (!existing.rows[0]) return res.status(404).json({ message: 'Not found' });

      const allowed = ['pending', 'accepted', 'in_progress', 'completed', 'declined'];
      if (status && !allowed.includes(status)) return res.status(400).json({ message: 'Invalid status' });

      const result = await query(
        `UPDATE referrals SET
           status = COALESCE($1, status),
           result_notes = COALESCE($2, result_notes),
           to_doctor_id = COALESCE($3, to_doctor_id),
           accepted_at = CASE WHEN $1 = 'accepted' THEN CURRENT_TIMESTAMP ELSE accepted_at END,
           completed_at = CASE WHEN $1 = 'completed' THEN CURRENT_TIMESTAMP ELSE completed_at END
         WHERE id = $4 RETURNING *`,
        [status || null, result_notes || null, to_doctor_id || null, req.params.id]
      );
      const row = result.rows[0];
      if (status === 'completed' || result_notes) {
        await notifyUser(
          deps,
          row.from_doctor_id,
          'Referral result returned',
          `${row.referral_code}: ${result_notes || 'Specialist completed the referral.'}`,
          'referral'
        );
        const patient = await patientUserId(row.patient_id);
        if (patient?.user_id) {
          await notifyUser(deps, patient.user_id, 'Specialist update', `${row.referral_code} is ${row.status}.`, 'referral');
        }
      }
      if (status === 'accepted') {
        const patient = await patientUserId(row.patient_id);
        if (patient?.user_id) {
          await notifyUser(deps, patient.user_id, 'Referral accepted', `${row.referral_code} was accepted by the specialist.`, 'referral');
        }
      }
      res.json(row);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/network/mine', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      const ids = await getAccessiblePatientIds(req.user!.id);
      const idList = ids.length ? ids : patient?.id ? [patient.id] : [];
      if (!idList.length) return res.json({ labs: [], scans: [], referrals: [], prescriptions: [] });

      const [labs, scans, referrals, prescriptions] = await Promise.all([
        query(
          `SELECT lr.*, o.name as partner_name
           FROM lab_requests lr LEFT JOIN partner_orgs o ON lr.partner_id = o.id
           WHERE lr.patient_id = ANY($1) ORDER BY lr.created_at DESC`,
          [idList]
        ),
        query(
          `SELECT sr.*, o.name as partner_name
           FROM scan_requests sr LEFT JOIN partner_orgs o ON sr.partner_id = o.id
           WHERE sr.patient_id = ANY($1) ORDER BY sr.created_at DESC`,
          [idList]
        ),
        query(
          `SELECT r.*, td.name as to_doctor_name, o.name as org_name
           FROM referrals r
           LEFT JOIN users td ON r.to_doctor_id = td.id
           LEFT JOIN partner_orgs o ON r.to_org_id = o.id
           WHERE r.patient_id = ANY($1) ORDER BY r.created_at DESC`,
          [idList]
        ),
        query(
          `SELECT pr.*, o.name as pharmacy_name
           FROM prescriptions pr LEFT JOIN partner_orgs o ON pr.pharmacy_id = o.id
           WHERE pr.patient_id = ANY($1) ORDER BY pr.created_at DESC`,
          [idList]
        ),
      ]);
      res.json({
        labs: labs.rows,
        scans: scans.rows,
        referrals: referrals.rows,
        prescriptions: prescriptions.rows,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });
}
