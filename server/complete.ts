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

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='bed_total') THEN
        ALTER TABLE partner_orgs ADD COLUMN bed_total INTEGER;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='bed_available') THEN
        ALTER TABLE partner_orgs ADD COLUMN bed_available INTEGER;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='icu_total') THEN
        ALTER TABLE partner_orgs ADD COLUMN icu_total INTEGER;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='icu_available') THEN
        ALTER TABLE partner_orgs ADD COLUMN icu_available INTEGER;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='network_status') THEN
        ALTER TABLE partner_orgs ADD COLUMN network_status VARCHAR(20) DEFAULT 'online';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='capacity_notes') THEN
        ALTER TABLE partner_orgs ADD COLUMN capacity_notes TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='capacity_updated_at') THEN
        ALTER TABLE partner_orgs ADD COLUMN capacity_updated_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='referrals' AND column_name='from_org_id') THEN
        ALTER TABLE referrals ADD COLUMN from_org_id INTEGER REFERENCES partner_orgs(id);
      END IF;
    END $$;
  `);

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
    await query(
      `UPDATE partner_orgs
       SET bed_total = COALESCE(bed_total, 120),
           bed_available = COALESCE(bed_available, 34),
           icu_total = COALESCE(icu_total, 8),
           icu_available = COALESCE(icu_available, 2),
           network_status = COALESCE(NULLIF(network_status, ''), 'online'),
           capacity_notes = COALESCE(capacity_notes, 'Demo ward board — update from Hospital desk → Capacity.'),
           capacity_updated_at = COALESCE(capacity_updated_at, CURRENT_TIMESTAMP)
       WHERE id = $1`,
      [hospOrg.rows[0].id]
    );
  }

  await seedHospitalNetworkDemo(hospOrg.rows[0]?.id || null, hospital.rows[0]?.id || null);
}

async function seedHospitalNetworkDemo(hospitalOrgId: number | null, hospitalUserId: number | null) {
  if (!hospitalOrgId) return;

  const patient = await query(`SELECT id FROM patients ORDER BY id ASC LIMIT 1`).catch(() => ({ rows: [] as any[] }));
  if (!patient.rows[0]) return;
  const patientId = patient.rows[0].id;

  const doctor = await query(
    `SELECT id FROM users WHERE role = 'doctor' ORDER BY id ASC LIMIT 1`
  ).catch(() => ({ rows: [] as any[] }));
  const doctorId = doctor.rows[0]?.id || hospitalUserId;

  const otherHospital = await query(
    `SELECT id, name FROM partner_orgs
     WHERE type = 'hospital' AND id <> $1 AND is_active = TRUE
     ORDER BY id ASC LIMIT 1`,
    [hospitalOrgId]
  ).catch(() => ({ rows: [] as any[] }));
  const fallbackDest = await query(
    `SELECT id, name FROM partner_orgs
     WHERE type IN ('imaging', 'laboratory') AND is_active = TRUE
     ORDER BY id ASC LIMIT 1`
  ).catch(() => ({ rows: [] as any[] }));
  const destOrg = otherHospital.rows[0] || fallbackDest.rows[0];

  const inboundOpen = await query(
    `SELECT COUNT(*)::int AS n FROM referrals
     WHERE to_org_id = $1 AND COALESCE(status,'pending') NOT IN ('completed','declined')`,
    [hospitalOrgId]
  ).catch(() => ({ rows: [{ n: 0 }] }));

  if (Number(inboundOpen.rows[0]?.n || 0) === 0 && doctorId) {
    const seq = await query(`SELECT nextval('referral_code_seq') AS n`);
    const code = `REF-${String(seq.rows[0].n).padStart(6, '0')}`;
    await query(
      `INSERT INTO referrals (
         referral_code, patient_id, from_doctor_id, to_org_id, specialty, reason,
         clinical_summary, urgency, status, from_org_id
       ) VALUES ($1,$2,$3,$4,'Internal medicine','Demo inbound — hypertension review',
         'Network demo referral for hospital desk intake.', 'urgent', 'pending', NULL)`,
      [code, patientId, doctorId, hospitalOrgId]
    ).catch(() => null);
  }

  const outboundOpen = await query(
    `SELECT COUNT(*)::int AS n FROM referrals WHERE from_org_id = $1`,
    [hospitalOrgId]
  ).catch(() => ({ rows: [{ n: 0 }] }));

  if (Number(outboundOpen.rows[0]?.n || 0) === 0 && destOrg && hospitalUserId) {
    const seq = await query(`SELECT nextval('referral_code_seq') AS n`);
    const code = `REF-${String(seq.rows[0].n).padStart(6, '0')}`;
    await query(
      `INSERT INTO referrals (
         referral_code, patient_id, from_doctor_id, to_org_id, specialty, reason,
         clinical_summary, urgency, status, from_org_id
       ) VALUES ($1,$2,$3,$4,'Cardiology','Demo outbound — capacity / specialty handoff',
         'Forwarded from regional desk when local capacity or specialty is constrained.', 'routine', 'accepted', $5)`,
      [code, patientId, hospitalUserId, destOrg.id, hospitalOrgId]
    ).catch(() => null);
  }

  // Soft partner status markers for same-region demo partners
  await query(
    `UPDATE partner_orgs
     SET network_status = CASE
           WHEN type = 'pharmacy' THEN COALESCE(NULLIF(network_status, ''), 'online')
           WHEN type = 'laboratory' THEN COALESCE(NULLIF(network_status, ''), 'busy')
           WHEN type = 'imaging' THEN COALESCE(NULLIF(network_status, ''), 'online')
           ELSE COALESCE(NULLIF(network_status, ''), 'online')
         END
     WHERE network_status IS NULL OR network_status = ''`
  ).catch(() => null);
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

      let org = await query(
        `SELECT o.* FROM partner_orgs o
         JOIN partner_staff s ON s.org_id = o.id
         WHERE s.user_id = $1 LIMIT 1`,
        [req.user!.id]
      );
      if (!org.rows[0] && ['admin', 'medical_ops'].includes(req.user!.role)) {
        org = await query(
          `SELECT * FROM partner_orgs WHERE type = 'hospital' AND is_active = TRUE ORDER BY id LIMIT 1`
        );
      }

      const hospital = org.rows[0] || null;
      const orgId = hospital?.id || null;
      const region = hospital?.region || null;

      const inbound = orgId
        ? await query(
            `SELECT r.*, p.full_name, p.patient_code, p.full_name as patient_name,
                    fd.name as from_doctor_name, fo.name as from_org_name
             FROM referrals r
             LEFT JOIN patients p ON p.id = r.patient_id
             LEFT JOIN users fd ON fd.id = r.from_doctor_id
             LEFT JOIN partner_orgs fo ON fo.id = r.from_org_id
             WHERE r.to_org_id = $1
             ORDER BY r.created_at DESC LIMIT 50`,
            [orgId]
          )
        : await query(
            `SELECT r.*, p.full_name, p.patient_code, p.full_name as patient_name,
                    fd.name as from_doctor_name, fo.name as from_org_name
             FROM referrals r
             LEFT JOIN patients p ON p.id = r.patient_id
             LEFT JOIN users fd ON fd.id = r.from_doctor_id
             LEFT JOIN partner_orgs fo ON fo.id = r.from_org_id
             ORDER BY r.created_at DESC LIMIT 50`
          );

      const outbound = orgId
        ? await query(
            `SELECT r.*, p.full_name, p.patient_code, p.full_name as patient_name,
                    o.name as to_org_name, o.type as to_org_type, o.region as to_org_region
             FROM referrals r
             LEFT JOIN patients p ON p.id = r.patient_id
             LEFT JOIN partner_orgs o ON o.id = r.to_org_id
             WHERE r.from_org_id = $1
             ORDER BY r.created_at DESC LIMIT 50`,
            [orgId]
          )
        : { rows: [] as any[] };

      const partners = await query(
        `SELECT id, name, type, region, town, phone, is_active, network_status,
                hours, services, bed_total, bed_available, icu_total, icu_available,
                capacity_updated_at
         FROM partner_orgs
         WHERE is_active = TRUE
           AND ($1::int IS NULL OR id <> $1)
           AND ($2::text IS NULL OR region = $2 OR type = 'hospital')
         ORDER BY
           CASE type WHEN 'hospital' THEN 0 WHEN 'laboratory' THEN 1 WHEN 'imaging' THEN 2 ELSE 3 END,
           name
         LIMIT 40`,
        [orgId, region]
      );

      const destinations = await query(
        `SELECT id, name, type, region, town, network_status
         FROM partner_orgs
         WHERE is_active = TRUE AND type IN ('hospital', 'laboratory', 'imaging')
           AND ($1::int IS NULL OR id <> $1)
         ORDER BY type, name
         LIMIT 60`,
        [orgId]
      );

      const bedTotal = Number(hospital?.bed_total ?? 0);
      const bedAvail = Number(hospital?.bed_available ?? 0);
      const icuTotal = Number(hospital?.icu_total ?? 0);
      const icuAvail = Number(hospital?.icu_available ?? 0);
      const inboundRows = inbound.rows;
      const outboundRows = outbound.rows;

      const stats = {
        inbound_open: inboundRows.filter(
          (r: any) => !['completed', 'declined'].includes(String(r.status || 'pending'))
        ).length,
        inbound_pending: inboundRows.filter((r: any) => String(r.status || 'pending') === 'pending').length,
        inbound_in_progress: inboundRows.filter((r: any) =>
          ['accepted', 'in_progress'].includes(String(r.status || ''))
        ).length,
        inbound_completed: inboundRows.filter((r: any) => String(r.status) === 'completed').length,
        outbound_open: outboundRows.filter(
          (r: any) => !['completed', 'declined'].includes(String(r.status || 'pending'))
        ).length,
        outbound_total: outboundRows.length,
        partners_online: partners.rows.filter(
          (p: any) => String(p.network_status || 'online') === 'online'
        ).length,
        partners_busy: partners.rows.filter((p: any) => String(p.network_status) === 'busy').length,
        partners_offline: partners.rows.filter(
          (p: any) => !p.is_active || String(p.network_status) === 'offline'
        ).length,
        bed_total: bedTotal,
        bed_available: bedAvail,
        bed_occupancy_pct: bedTotal ? Math.round(((bedTotal - bedAvail) / bedTotal) * 100) : 0,
        icu_total: icuTotal,
        icu_available: icuAvail,
      };

      res.json({
        hospital,
        capacity: hospital
          ? {
              bed_total: bedTotal,
              bed_available: bedAvail,
              icu_total: icuTotal,
              icu_available: icuAvail,
              network_status: hospital.network_status || 'online',
              capacity_notes: hospital.capacity_notes || null,
              capacity_updated_at: hospital.capacity_updated_at || null,
              occupancy_pct: stats.bed_occupancy_pct,
            }
          : null,
        stats,
        inbound: inboundRows,
        outbound: outboundRows,
        referrals: inboundRows,
        partners: partners.rows,
        destinations: destinations.rows,
        note:
          'Hospital network desk: accept inbound specialist referrals, post outbound transfers, publish bed/ICU capacity, and watch regional partner status.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/hospital/capacity', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      if (!['hospital', 'admin', 'medical_ops'].includes(req.user!.role)) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      const staffOrg = await query(
        `SELECT o.id FROM partner_orgs o
         JOIN partner_staff s ON s.org_id = o.id
         WHERE s.user_id = $1 LIMIT 1`,
        [req.user!.id]
      );
      let orgId = staffOrg.rows[0]?.id as number | undefined;
      if (!orgId && ['admin', 'medical_ops'].includes(req.user!.role) && req.body?.org_id) {
        orgId = Number(req.body.org_id);
      }
      if (!orgId) return res.status(400).json({ message: 'No hospital organisation linked to this account' });

      const bedTotal =
        req.body?.bed_total !== undefined && req.body?.bed_total !== null
          ? Math.max(0, Number(req.body.bed_total))
          : null;
      const bedAvailable =
        req.body?.bed_available !== undefined && req.body?.bed_available !== null
          ? Math.max(0, Number(req.body.bed_available))
          : null;
      const icuTotal =
        req.body?.icu_total !== undefined && req.body?.icu_total !== null
          ? Math.max(0, Number(req.body.icu_total))
          : null;
      const icuAvailable =
        req.body?.icu_available !== undefined && req.body?.icu_available !== null
          ? Math.max(0, Number(req.body.icu_available))
          : null;
      const statusRaw = req.body?.network_status ? String(req.body.network_status) : null;
      const networkStatus =
        statusRaw && ['online', 'busy', 'offline'].includes(statusRaw) ? statusRaw : null;
      const notes =
        req.body?.capacity_notes !== undefined ? String(req.body.capacity_notes).slice(0, 500) : null;

      const updated = await query(
        `UPDATE partner_orgs SET
           bed_total = COALESCE($1, bed_total),
           bed_available = COALESCE($2, bed_available),
           icu_total = COALESCE($3, icu_total),
           icu_available = COALESCE($4, icu_available),
           network_status = COALESCE($5, network_status),
           capacity_notes = COALESCE($6, capacity_notes),
           capacity_updated_at = CURRENT_TIMESTAMP
         WHERE id = $7
         RETURNING id, name, type, region, town, bed_total, bed_available, icu_total, icu_available,
                   network_status, capacity_notes, capacity_updated_at`,
        [bedTotal, bedAvailable, icuTotal, icuAvailable, networkStatus, notes, orgId]
      );
      if (!updated.rows[0]) return res.status(404).json({ message: 'Hospital not found' });

      const row = updated.rows[0];
      const bt = Number(row.bed_total || 0);
      const ba = Number(row.bed_available || 0);
      if (ba > bt && bt > 0) {
        await query(`UPDATE partner_orgs SET bed_available = bed_total WHERE id = $1`, [orgId]);
        row.bed_available = row.bed_total;
      }
      res.json({
        ...row,
        occupancy_pct: bt ? Math.round(((bt - Number(row.bed_available || 0)) / bt) * 100) : 0,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not update capacity' });
    }
  });

  app.post('/api/hospital/referrals/outbound', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      if (!['hospital', 'admin', 'medical_ops'].includes(req.user!.role)) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      const staffOrg = await query(
        `SELECT o.* FROM partner_orgs o
         JOIN partner_staff s ON s.org_id = o.id
         WHERE s.user_id = $1 LIMIT 1`,
        [req.user!.id]
      );
      const fromOrg = staffOrg.rows[0];
      if (!fromOrg && req.user!.role === 'hospital') {
        return res.status(400).json({ message: 'No hospital organisation linked to this account' });
      }

      const { patient_code, patient_id, to_org_id, specialty, reason, clinical_summary, urgency } =
        req.body || {};
      if (!to_org_id || !reason) {
        return res.status(400).json({ message: 'Destination facility and reason are required' });
      }

      let patientId = patient_id ? Number(patient_id) : null;
      if (!patientId && patient_code) {
        const found = await query(
          `SELECT id FROM patients WHERE UPPER(patient_code) = UPPER($1) LIMIT 1`,
          [String(patient_code).trim()]
        );
        patientId = found.rows[0]?.id || null;
      }
      if (!patientId) return res.status(400).json({ message: 'Patient ID or patient code is required' });

      const dest = await query(
        `SELECT * FROM partner_orgs WHERE id = $1 AND is_active = TRUE`,
        [Number(to_org_id)]
      );
      if (!dest.rows[0]) return res.status(404).json({ message: 'Destination facility not found' });
      if (fromOrg && Number(dest.rows[0].id) === Number(fromOrg.id)) {
        return res.status(400).json({ message: 'Choose a different destination facility' });
      }

      const seq = await query(`SELECT nextval('referral_code_seq') AS n`);
      const code = `REF-${String(seq.rows[0].n).padStart(6, '0')}`;
      const inserted = await query(
        `INSERT INTO referrals (
           referral_code, patient_id, from_doctor_id, to_org_id, from_org_id,
           specialty, reason, clinical_summary, urgency, status
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'pending') RETURNING *`,
        [
          code,
          patientId,
          req.user!.id,
          dest.rows[0].id,
          fromOrg?.id || null,
          specialty || null,
          String(reason).trim(),
          clinical_summary || null,
          urgency || 'routine',
        ]
      );

      const destStaff = await query(`SELECT user_id FROM partner_staff WHERE org_id = $1`, [
        dest.rows[0].id,
      ]);
      for (const s of destStaff.rows) {
        await query(
          `INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, $4)`,
          [
            s.user_id,
            'Inbound hospital referral',
            `${code}: ${specialty || 'transfer'} — ${String(reason).trim()}`,
            'referral',
          ]
        );
      }

      const patient = await query(`SELECT user_id, full_name, patient_code FROM patients WHERE id = $1`, [
        patientId,
      ]);
      if (patient.rows[0]?.user_id) {
        await query(
          `INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, $4)`,
          [
            patient.rows[0].user_id,
            'Facility transfer arranged',
            `${code} → ${dest.rows[0].name}`,
            'referral',
          ]
        );
      }

      res.status(201).json({
        ...inserted.rows[0],
        to_org_name: dest.rows[0].name,
        patient_name: patient.rows[0]?.full_name,
        patient_code: patient.rows[0]?.patient_code,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not create outbound referral' });
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
