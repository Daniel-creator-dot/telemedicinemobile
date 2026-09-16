import type { Express, Response } from 'express';
import bcrypt from 'bcryptjs';
import { query } from './db';
import {
  authenticate,
  AuthedRequest,
  canAccessPatient,
  ADMIN_OPS,
  requireRoles,
} from './authz';
import { getAccessiblePatientIds, getPatientForUser } from './patients';
import { getEligibility } from './phase3';

export async function initCompleteSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS support_tickets (
      id SERIAL PRIMARY KEY,
      ticket_code VARCHAR(30) UNIQUE,
      user_id INTEGER REFERENCES users(id),
      patient_id INTEGER REFERENCES patients(id),
      topic VARCHAR(80) NOT NULL,
      body TEXT NOT NULL,
      status VARCHAR(20) DEFAULT 'open',
      priority VARCHAR(20) DEFAULT 'normal',
      assignee_id INTEGER REFERENCES users(id),
      resolution TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await query(`CREATE SEQUENCE IF NOT EXISTS ticket_code_seq START 600001`);

  const support = await query("SELECT id FROM users WHERE username = 'support' LIMIT 1");
  if (!support.rows[0]) {
    const hashed = await bcrypt.hash('support123', 10);
    await query(
      `INSERT INTO users (username, password, role, name, phone_number)
       VALUES ('support', $1, 'admin', 'Medilynks Support', '0240000301')`,
      [hashed]
    );
    console.log('Support desk user created (support/support123) — admin role for ticket queue');
  }

  let hospital = await query("SELECT id FROM users WHERE username = 'hospital' LIMIT 1");
  if (!hospital.rows[0]) {
    const hashed = await bcrypt.hash('hosp123', 10);
    hospital = await query(
      `INSERT INTO users (username, password, role, name, phone_number)
       VALUES ('hospital', $1, 'hospital', 'Regional Hospital Desk', '0240000401') RETURNING id`,
      [hashed]
    );
    console.log('Hospital desk user created (hospital/hosp123)');
  }
  const hospOrg = await query(
    `SELECT id FROM partner_orgs WHERE type = 'hospital' ORDER BY id LIMIT 1`
  );
  if (hospOrg.rows[0] && hospital.rows[0]) {
    await query(
      `INSERT INTO partner_staff (org_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
      [hospOrg.rows[0].id, hospital.rows[0].id]
    );
  }
}

export function registerCompleteRoutes(app: Express) {
  app.get('/api/billing/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const ids = req.user!.role === 'patient' ? await getAccessiblePatientIds(req.user!.id) : [];
      let patientId = req.query.patient_id ? Number(req.query.patient_id) : null;
      if (req.user!.role === 'patient') {
        patientId = patientId && ids.includes(patientId) ? patientId : ids[0] || null;
      } else if (patientId && !(await canAccessPatient(req.user!, patientId))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      if (!patientId) return res.json({ eligibility: null, payments: [], receipts: [], outstanding: [] });

      const [eligibility, payments, visits] = await Promise.all([
        query(
          `SELECT * FROM payments WHERE appointment_id IN (SELECT id FROM appointments WHERE patient_id = $1)
           ORDER BY created_at DESC LIMIT 40`,
          [patientId]
        ).catch(() => ({ rows: [] as any[] })),
        query(
          `SELECT p.*, a.appointment_id, a.preferred_date, a.preferred_time, a.service, a.payment_status, a.payment_ref
           FROM payments p
           LEFT JOIN appointments a ON a.id = p.appointment_id
           WHERE a.patient_id = $1
           ORDER BY p.created_at DESC LIMIT 40`,
          [patientId]
        ).catch(() => ({ rows: [] as any[] })),
        query(
          `SELECT id, appointment_id, preferred_date, preferred_time, service, payment_status, payment_ref, status
           FROM appointments WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 30`,
          [patientId]
        ),
      ]);

      const receipts = visits.rows
        .filter((v: any) => v.payment_status === 'paid' || v.payment_ref)
        .map((v: any) => {
          const pay = payments.rows.find((p: any) => Number(p.appointment_id) === Number(v.id));
          const gateway =
            pay?.gateway ||
            (String(v.payment_ref || '').startsWith('digidemo_')
              ? 'demo'
              : String(v.payment_ref || '').startsWith('digihealth_')
                ? 'paystack'
                : 'paystack');
          return {
            receipt_no: v.payment_ref || `R-${v.id}`,
            appointment_code: v.appointment_id,
            date: v.preferred_date,
            time: v.preferred_time,
            service: v.service || 'Consultation',
            amount: pay?.copay_amount ?? pay?.amount ?? 50,
            currency: 'GHS',
            gateway,
            note:
              gateway === 'demo'
                ? 'Demo confirmation (Paystack keys not configured).'
                : gateway === 'paystack'
                  ? 'Collected via Paystack (card, MoMo, or bank).'
                  : 'Visit collection recorded.',
          };
        });

      const cover = await getEligibility(patientId);
      const outstanding = visits.rows
        .filter(
          (v: any) =>
            v.payment_status !== 'paid' &&
            !['cancelled', 'completed', 'no_show'].includes(String(v.status || ''))
        )
        .map((v: any) => ({
          id: v.id,
          appointment_code: v.appointment_id,
          date: v.preferred_date,
          time: v.preferred_time,
          service: v.service || 'Consultation',
          status: v.status,
          copay: cover.copay,
          currency: 'GHS',
        }));

      res.json({
        payments: payments.rows.length ? payments.rows : eligibility.rows,
        receipts,
        outstanding,
        eligibility: cover,
        disclaimer:
          'Visit copay uses Paystack (card / MoMo / bank) when keys are set. Without keys, the app confirms an offline demo payment so booking and Consult Now still complete.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/followups/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const ids = req.user!.role === 'patient' ? await getAccessiblePatientIds(req.user!.id) : [];
      if (req.user!.role === 'patient' && !ids.length) return res.json([]);
      if (['doctor', 'nurse', 'medical_ops', 'admin'].includes(req.user!.role)) {
        const rows = await query(
          `SELECT c.id, c.follow_up_date, c.diagnosis, c.status, p.full_name, p.patient_code, a.appointment_id
           FROM consultations c
           JOIN appointments a ON a.id = c.appointment_id
           LEFT JOIN patients p ON p.id = a.patient_id
           WHERE c.follow_up_date IS NOT NULL
           ORDER BY c.follow_up_date ASC LIMIT 80`
        );
        return res.json(rows.rows);
      }
      const rows = await query(
        `SELECT c.id, c.follow_up_date, c.status, a.appointment_id, a.preferred_date, a.service
         FROM consultations c
         JOIN appointments a ON a.id = c.appointment_id
         WHERE a.patient_id = ANY($1) AND c.follow_up_date IS NOT NULL
         ORDER BY c.follow_up_date ASC`,
        [ids]
      );
      res.json(rows.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/support/tickets', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      if (ADMIN_OPS.includes(req.user!.role) || req.user!.role === 'admin') {
        const rows = await query(
          `SELECT t.*, u.name as user_name, u.username, p.full_name, p.patient_code
           FROM support_tickets t
           LEFT JOIN users u ON u.id = t.user_id
           LEFT JOIN patients p ON p.id = t.patient_id
           ORDER BY t.created_at DESC LIMIT 100`
        );
        return res.json(rows.rows);
      }
      const rows = await query(
        `SELECT * FROM support_tickets WHERE user_id = $1 ORDER BY created_at DESC`,
        [req.user!.id]
      );
      res.json(rows.rows);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/support/tickets', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const topic = String(req.body?.topic || '').trim() || 'general';
      const body = String(req.body?.body || '').trim();
      if (body.length < 8) return res.status(400).json({ message: 'Please describe the issue.' });
      const patient = await getPatientForUser(req.user!.id);
      const codeRow = await query(`SELECT nextval('ticket_code_seq') AS n`);
      const ticketCode = `SUP-${String(codeRow.rows[0].n).padStart(6, '0')}`;
      const row = await query(
        `INSERT INTO support_tickets (ticket_code, user_id, patient_id, topic, body, priority)
         VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
        [ticketCode, req.user!.id, patient?.id || null, topic, body, req.body?.priority || 'normal']
      );
      res.status(201).json(row.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not open ticket' });
    }
  });

  app.get('/api/hospital/desk', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      if (!['hospital', 'admin', 'medical_ops'].includes(req.user!.role)) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      const org = await query(
        `SELECT o.* FROM partner_orgs o
         JOIN partner_staff s ON s.org_id = o.id
         WHERE s.user_id = $1 LIMIT 1`,
        [req.user!.id]
      );
      const orgId = org.rows[0]?.id || null;
      const referrals = orgId
        ? await query(
            `SELECT r.*, p.full_name, p.patient_code
             FROM referrals r
             LEFT JOIN patients p ON p.id = r.patient_id
             WHERE r.to_org_id = $1
             ORDER BY r.created_at DESC LIMIT 40`,
            [orgId]
          )
        : await query(
            `SELECT r.*, p.full_name, p.patient_code
             FROM referrals r
             LEFT JOIN patients p ON p.id = r.patient_id
             ORDER BY r.created_at DESC LIMIT 40`
          );
      res.json({
        hospital: org.rows[0] || null,
        referrals: referrals.rows,
        note: 'Hospital desk coordinates inbound specialist referrals from the Medilynks network.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/support/tickets/:id', authenticate, requireRoles(...ADMIN_OPS), async (req: AuthedRequest, res) => {
    try {
      const row = await query(
        `UPDATE support_tickets
         SET status = COALESCE($1, status),
             resolution = COALESCE($2, resolution),
             assignee_id = COALESCE($3, assignee_id),
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $4 RETURNING *`,
        [req.body?.status || null, req.body?.resolution || null, req.user!.id, req.params.id]
      );
      if (!row.rows[0]) return res.status(404).json({ message: 'Not found' });
      res.json(row.rows[0]);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });
}
