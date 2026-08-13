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

export function registerClinicalRoutes(app: Express) {
  app.get('/api/journey/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.json({ events: [] });

      const [apts, labs, scans, rxs, refs] = await Promise.all([
        query(
          `SELECT a.id, a.appointment_id, a.status, a.consult_type, a.service, a.preferred_date, a.preferred_time,
                  a.created_at, d.name as doctor_name
           FROM appointments a LEFT JOIN doctors d ON a.doctor_id = d.id
           WHERE a.patient_id = $1 ORDER BY a.created_at DESC LIMIT 40`,
          [patient.id]
        ),
        query(
          `SELECT id, test_name, status, created_at, result_returned_at, partner_id FROM lab_requests
           WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 20`,
          [patient.id]
        ),
        query(
          `SELECT id, scan_type, status, created_at, result_returned_at FROM scan_requests
           WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 20`,
          [patient.id]
        ),
        query(
          `SELECT id, medication_name, status, prescription_ref, created_at FROM prescriptions
           WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 20`,
          [patient.id]
        ),
        query(
          `SELECT id, specialty, status, reason, created_at FROM referrals
           WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 20`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
      ]);

      const events = [
        ...apts.rows.map((r: any) => ({
          kind: 'consultation',
          title: r.consult_type || r.service || 'Consultation',
          subtitle: r.doctor_name ? `With ${r.doctor_name}` : 'Clinician to be assigned',
          status: r.status,
          at: r.created_at || r.preferred_date,
          ref: r.appointment_id,
        })),
        ...labs.rows.map((r: any) => ({
          kind: 'lab',
          title: r.test_name || 'Laboratory request',
          subtitle: r.status === 'completed' ? 'Results available' : 'Investigation in progress',
          status: r.status,
          at: r.created_at,
        })),
        ...scans.rows.map((r: any) => ({
          kind: 'imaging',
          title: r.scan_type || 'Imaging request',
          subtitle: r.status === 'completed' ? 'Report available' : 'Imaging in progress',
          status: r.status,
          at: r.created_at,
        })),
        ...rxs.rows.map((r: any) => ({
          kind: 'prescription',
          title: r.medication_name,
          subtitle: r.prescription_ref || 'Electronic prescription',
          status: r.status,
          at: r.created_at,
        })),
        ...refs.rows.map((r: any) => ({
          kind: 'referral',
          title: r.specialty || 'Specialist referral',
          subtitle: r.reason || 'Closed-loop referral',
          status: r.status,
          at: r.created_at,
        })),
      ].sort((a, b) => new Date(b.at || 0).getTime() - new Date(a.at || 0).getTime());

      res.json({
        patient_code: patient.patient_code,
        events,
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
          `SELECT * FROM vault_documents WHERE patient_id = $1 ORDER BY created_at DESC`,
          [patient.id]
        ).catch(() => ({ rows: [] })),
      ]);

      res.json({
        prescriptions: rxs.rows,
        labs: labs.rows,
        scans: scans.rows,
        letters: consults.rows,
        documents: docs.rows,
        storage_note: 'Uploaded files are not stored on this API. Documents are metadata you add (title, source, notes).',
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
