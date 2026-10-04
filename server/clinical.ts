import type { Express, Response } from 'express';
import { query } from './db';
import {
  authenticate,
  AuthedRequest,
  canAccessPatient,
} from './authz';
import { getPatientForUser } from './patients';

export async function initClinicalSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS health_measurements (
      id SERIAL PRIMARY KEY,
      patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      kind VARCHAR(40) NOT NULL,
      value_primary VARCHAR(40) NOT NULL,
      value_secondary VARCHAR(40),
      unit VARCHAR(20),
      notes TEXT,
      recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS dependents (
      id SERIAL PRIMARY KEY,
      guardian_patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      dependent_patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      relationship VARCHAR(40) NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE (guardian_patient_id, dependent_patient_id)
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS chronic_programs (
      id SERIAL PRIMARY KEY,
      patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      condition VARCHAR(80) NOT NULL,
      status VARCHAR(30) DEFAULT 'active',
      next_review DATE,
      notes TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);
}

function journeyIsOpen(kind: string, status: string) {
  const s = (status || '').toLowerCase();
  if (kind === 'prescription') return !['dispensed', 'cancelled', 'unsent'].includes(s);
  if (kind === 'lab' || kind === 'imaging') return !['completed', 'cancelled'].includes(s);
  if (kind === 'referral') return !['completed', 'cancelled'].includes(s);
  if (kind === 'consultation') {
    return ['queued', 'pending', 'approved', 'consulting', 'arrived', 'waiting', 'triage'].includes(s);
  }
  return false;
}

function journeyStatusLabel(kind: string, status: string) {
  const s = (status || '').toLowerCase();
  const labels: Record<string, string> = {
    unsent: 'Not sent',
    sent: 'Sent to pharmacy',
    received: 'Pharmacy received',
    preparing: 'Preparing',
    ready: 'Ready for pickup',
    dispensed: 'Dispensed',
    unavailable: 'Unavailable',
    pending: 'Pending',
    scheduled: 'Scheduled',
    sample_collected: 'Sample collected',
    processing: 'Processing',
    completed: 'Completed',
    cancelled: 'Cancelled',
    queued: 'In queue',
    approved: 'Approved',
    consulting: 'In consult',
    arrived: 'Checked in',
    waiting: 'Waiting',
    triage: 'In triage',
    accepted: 'Accepted',
  };
  if (labels[s]) return labels[s];
  if (kind === 'consultation') return s.replace(/_/g, ' ');
  return s.replace(/_/g, ' ') || 'In progress';
}

function journeySubtitle(kind: string, status: string, partner?: string | null, ref?: string | null) {
  const loc = partner ? ` · ${partner}` : '';
  const s = (status || '').toLowerCase();
  if (kind === 'lab') {
    if (s === 'completed') return `Results returned${loc}`;
    if (s === 'sample_collected') return `Sample collected${loc}`;
    if (s === 'processing') return `Processing at lab${loc}`;
    return `Lab request${loc || ' · Awaiting collection'}`;
  }
  if (kind === 'imaging') {
    if (s === 'completed') return `Report available${loc}`;
    if (s === 'scheduled') return `Appointment scheduled${loc}`;
    return `Imaging request${loc || ' · In progress'}`;
  }
  if (kind === 'prescription') {
    if (s === 'unsent') return ref ? 'Prescription on chart' : 'Not yet sent to pharmacy';
    if (s === 'ready') return `Ready for pickup${loc}`;
    if (s === 'dispensed') return `Collected${loc}`;
    return `${journeyStatusLabel(kind, s)}${loc}`;
  }
  if (kind === 'referral') {
    return partner ? `Referred to ${partner}` : 'Specialist referral on network';
  }
  return ref || 'Care event on your chart';
}

export function registerClinicalRoutes(app: Express) {
  app.get('/api/journey/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.json({ events: [], open_count: 0, active: [] });

      const [apts, labs, scans, rxs, refs] = await Promise.all([
        query(
          `SELECT a.id, a.appointment_id, a.status, a.consult_type, a.service, a.preferred_date, a.preferred_time,
                  a.created_at, d.name as doctor_name
           FROM appointments a LEFT JOIN doctors d ON a.doctor_id = d.id
           WHERE a.patient_id = $1 ORDER BY a.created_at DESC LIMIT 40`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT lr.id, lr.test_name, lr.status, lr.created_at, lr.completed_at, o.name as partner_name
           FROM lab_requests lr
           LEFT JOIN partner_orgs o ON lr.partner_id = o.id
           WHERE lr.patient_id = $1 ORDER BY lr.created_at DESC LIMIT 20`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT sr.id, sr.scan_type, sr.status, sr.created_at, sr.completed_at, o.name as partner_name
           FROM scan_requests sr
           LEFT JOIN partner_orgs o ON sr.partner_id = o.id
           WHERE sr.patient_id = $1 ORDER BY sr.created_at DESC LIMIT 20`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT pr.id, pr.medication_name, COALESCE(pr.dispense_status, 'unsent') AS status,
                  pr.prescription_ref, pr.created_at, o.name as pharmacy_name
           FROM prescriptions pr
           LEFT JOIN partner_orgs o ON pr.pharmacy_id = o.id
           WHERE pr.patient_id = $1 ORDER BY pr.created_at DESC LIMIT 20`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT r.id, r.specialty, r.status, r.reason, r.created_at, o.name as org_name
           FROM referrals r
           LEFT JOIN partner_orgs o ON r.to_org_id = o.id
           WHERE r.patient_id = $1 ORDER BY r.created_at DESC LIMIT 20`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
      ]);

      const events = [
        ...apts.rows.map((r: any) => {
          const status = r.status;
          return {
            kind: 'consultation',
            title: r.consult_type || r.service || 'Consultation',
            subtitle: r.doctor_name ? `With ${r.doctor_name}` : 'Clinician to be assigned',
            status,
            status_label: journeyStatusLabel('consultation', status),
            partner_name: r.doctor_name || null,
            is_open: journeyIsOpen('consultation', status),
            at: r.created_at || r.preferred_date,
            ref: r.appointment_id,
          };
        }),
        ...labs.rows.map((r: any) => {
          const status = r.status || 'pending';
          return {
            kind: 'lab',
            title: r.test_name || 'Laboratory request',
            subtitle: journeySubtitle('lab', status, r.partner_name),
            status,
            status_label: journeyStatusLabel('lab', status),
            partner_name: r.partner_name || null,
            is_open: journeyIsOpen('lab', status),
            at: r.created_at,
          };
        }),
        ...scans.rows.map((r: any) => {
          const status = r.status || 'pending';
          return {
            kind: 'imaging',
            title: r.scan_type || 'Imaging request',
            subtitle: journeySubtitle('imaging', status, r.partner_name),
            status,
            status_label: journeyStatusLabel('imaging', status),
            partner_name: r.partner_name || null,
            is_open: journeyIsOpen('imaging', status),
            at: r.created_at,
          };
        }),
        ...rxs.rows.map((r: any) => {
          const status = r.status || 'unsent';
          return {
            kind: 'prescription',
            title: r.medication_name,
            subtitle: journeySubtitle('prescription', status, r.pharmacy_name, r.prescription_ref),
            status,
            status_label: journeyStatusLabel('prescription', status),
            partner_name: r.pharmacy_name || null,
            is_open: journeyIsOpen('prescription', status),
            at: r.created_at,
            ref: r.prescription_ref,
          };
        }),
        ...refs.rows.map((r: any) => {
          const status = r.status || 'pending';
          return {
            kind: 'referral',
            title: r.specialty || 'Specialist referral',
            subtitle: journeySubtitle('referral', status, r.org_name) + (r.reason ? ` · ${r.reason}` : ''),
            status,
            status_label: journeyStatusLabel('referral', status),
            partner_name: r.org_name || null,
            is_open: journeyIsOpen('referral', status),
            at: r.created_at,
          };
        }),
      ].sort((a, b) => new Date(b.at || 0).getTime() - new Date(a.at || 0).getTime());

      const open = events.filter((e) => e.is_open);

      res.json({
        patient_code: patient.patient_code,
        events,
        open_count: open.length,
        active: open.slice(0, 6),
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/vault/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.json({ prescriptions: [], labs: [], scans: [], letters: [], documents: [] });

      const [rxs, labs, scans, consults, docs] = await Promise.all([
        query(
          `SELECT pr.*, a.appointment_id as apt_code FROM prescriptions pr
           JOIN appointments a ON pr.appointment_id = a.id
           WHERE pr.patient_id = $1 ORDER BY pr.created_at DESC`,
          [patient.id]
        ),
        query(
          `SELECT * FROM lab_requests WHERE patient_id = $1 ORDER BY created_at DESC`,
          [patient.id]
        ),
        query(
          `SELECT * FROM scan_requests WHERE patient_id = $1 ORDER BY created_at DESC`,
          [patient.id]
        ),
        query(
          `SELECT c.id, c.working_diagnosis, c.diagnosis, c.treatment_plan, c.patient_education,
                  c.created_at, u.name as doctor_name
           FROM consultations c LEFT JOIN users u ON c.doctor_id = u.id
           WHERE c.patient_id = $1 AND c.status = 'completed' ORDER BY c.created_at DESC`,
          [patient.id]
        ),
        query(
          `SELECT id, patient_id, title, kind, notes, source_label, created_by, created_at,
                  file_name, mime_type, byte_size, (content IS NOT NULL) AS has_file
           FROM vault_documents WHERE patient_id = $1 ORDER BY created_at DESC`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
      ]);

      res.json({
        prescriptions: rxs.rows,
        labs: labs.rows,
        scans: scans.rows,
        letters: consults.rows,
        documents: docs.rows,
        storage_note: 'Letters, labs, imaging, and prescriptions from visits stay here. You can also attach a photo or PDF (up to 2 MB) — stored in the clinic database, not on this server disk.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/tracker', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      let patientId = req.query.patient_id ? Number(req.query.patient_id) : null;
      if (req.user!.role === 'patient') {
        const patient = await getPatientForUser(req.user!.id);
        patientId = patient?.id || null;
      } else if (patientId && !(await canAccessPatient(req.user!, patientId))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      if (!patientId) return res.json([]);
      const result = await query(
        `SELECT * FROM health_measurements WHERE patient_id = $1 ORDER BY recorded_at DESC LIMIT 200`,
        [patientId]
      );
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/tracker', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const patient = req.user!.role === 'patient'
        ? await getPatientForUser(req.user!.id)
        : null;
      const patientId = patient?.id || req.body.patient_id;
      if (!patientId) return res.status(400).json({ message: 'Patient required' });
      if (!(await canAccessPatient(req.user!, patientId))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      const { kind, value_primary, value_secondary, unit, notes } = req.body;
      if (!kind || !value_primary) {
        return res.status(400).json({ message: 'Measurement type and value are required' });
      }
      const result = await query(
        `INSERT INTO health_measurements (patient_id, kind, value_primary, value_secondary, unit, notes)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
        [patientId, kind, value_primary, value_secondary || null, unit || null, notes || null]
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

}
