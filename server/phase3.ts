import type { Express, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import { query } from './db';
import { getPatientForUser } from './phase1';
import { commercialOrgId } from './phase5';
import { GENERAL_CONSULT_FEE, getActiveMembership, membershipEligibilityOverlay } from './membership';
import { isDemoPaymentReference, refundPaystackTransaction } from './paystack';

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

/** General consultation self-pay / billed fee (GHS). */
export const CONSULT_FEE = GENERAL_CONSULT_FEE;
const DOCTOR_SHARE = 40;

export async function initPhase3Schema() {
  await query(`CREATE SEQUENCE IF NOT EXISTS preauth_code_seq START 300001`);
  await query(`CREATE SEQUENCE IF NOT EXISTS claim_code_seq START 400001`);
  await query(`CREATE SEQUENCE IF NOT EXISTS settlement_code_seq START 500001`);

  await query(`
    CREATE TABLE IF NOT EXISTS corporates (
      id SERIAL PRIMARY KEY,
      name VARCHAR(160) NOT NULL,
      industry VARCHAR(80),
      region VARCHAR(80),
      town VARCHAR(80),
      contact_name VARCHAR(100),
      contact_phone VARCHAR(20),
      coverage_percent DECIMAL(5,2) DEFAULT 60,
      copay_amount DECIMAL(10,2) DEFAULT 20,
      annual_limit DECIMAL(12,2) DEFAULT 3000,
      is_active BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS corporate_members (
      id SERIAL PRIMARY KEY,
      corporate_id INTEGER REFERENCES corporates(id) ON DELETE CASCADE,
      patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      staff_id VARCHAR(50),
      department VARCHAR(100),
      status VARCHAR(20) DEFAULT 'active',
      enrolled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(corporate_id, patient_id)
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS insurers (
      id SERIAL PRIMARY KEY,
      name VARCHAR(160) NOT NULL,
      plan_name VARCHAR(120),
      region VARCHAR(80),
      coverage_percent DECIMAL(5,2) DEFAULT 80,
      copay_amount DECIMAL(10,2) DEFAULT 10,
      annual_limit DECIMAL(12,2) DEFAULT 5000,
      is_active BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS policies (
      id SERIAL PRIMARY KEY,
      insurer_id INTEGER REFERENCES insurers(id) ON DELETE CASCADE,
      patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      policy_number VARCHAR(60) UNIQUE,
      status VARCHAR(20) DEFAULT 'active',
      starts_on DATE DEFAULT CURRENT_DATE,
      ends_on DATE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS preauths (
      id SERIAL PRIMARY KEY,
      preauth_code VARCHAR(30) UNIQUE,
      appointment_id INTEGER REFERENCES appointments(id),
      patient_id INTEGER REFERENCES patients(id),
      policy_id INTEGER REFERENCES policies(id),
      corporate_id INTEGER REFERENCES corporates(id),
      service VARCHAR(120),
      requested_amount DECIMAL(10,2) DEFAULT 50,
      approved_amount DECIMAL(10,2),
      status VARCHAR(20) DEFAULT 'pending',
      notes TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      decided_at TIMESTAMP,
      decided_by INTEGER REFERENCES users(id)
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS claims (
      id SERIAL PRIMARY KEY,
      claim_code VARCHAR(30) UNIQUE,
      appointment_id INTEGER REFERENCES appointments(id),
      patient_id INTEGER REFERENCES patients(id),
      policy_id INTEGER REFERENCES policies(id),
      corporate_id INTEGER REFERENCES corporates(id),
      source VARCHAR(20),
      amount DECIMAL(10,2) NOT NULL,
      status VARCHAR(20) DEFAULT 'submitted',
      notes TEXT,
      submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      paid_at TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS settlements (
      id SERIAL PRIMARY KEY,
      settlement_code VARCHAR(30) UNIQUE,
      payee_type VARCHAR(30) NOT NULL,
      payee_name VARCHAR(160),
      payee_user_id INTEGER REFERENCES users(id),
      payee_org_id INTEGER,
      amount DECIMAL(10,2) NOT NULL,
      status VARCHAR(20) DEFAULT 'pending',
      notes TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      paid_at TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS doctor_earnings (
      id SERIAL PRIMARY KEY,
      doctor_user_id INTEGER REFERENCES users(id),
      appointment_id INTEGER REFERENCES appointments(id),
      amount DECIMAL(10,2) NOT NULL,
      status VARCHAR(20) DEFAULT 'accrued',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(appointment_id)
    );
  `);

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payments' AND column_name='coverage_source') THEN
        ALTER TABLE payments ADD COLUMN coverage_source VARCHAR(20);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payments' AND column_name='covered_amount') THEN
        ALTER TABLE payments ADD COLUMN covered_amount DECIMAL(10,2) DEFAULT 0;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payments' AND column_name='copay_amount') THEN
        ALTER TABLE payments ADD COLUMN copay_amount DECIMAL(10,2) DEFAULT 50;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payments' AND column_name='reconciled_at') THEN
        ALTER TABLE payments ADD COLUMN reconciled_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payments' AND column_name='reconciled_by') THEN
        ALTER TABLE payments ADD COLUMN reconciled_by INTEGER REFERENCES users(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payments' AND column_name='refunded_at') THEN
        ALTER TABLE payments ADD COLUMN refunded_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='payments' AND column_name='refund_notes') THEN
        ALTER TABLE payments ADD COLUMN refund_notes TEXT;
      END IF;
    END $$;
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS coverage_directory (
      id SERIAL PRIMARY KEY,
      source VARCHAR(20) NOT NULL,
      insurer_id INTEGER REFERENCES insurers(id) ON DELETE CASCADE,
      corporate_id INTEGER REFERENCES corporates(id) ON DELETE CASCADE,
      member_key VARCHAR(80) NOT NULL,
      member_name VARCHAR(160),
      status VARCHAR(20) DEFAULT 'eligible',
      claimed_patient_id INTEGER REFERENCES patients(id),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(source, member_key)
    );
  `);

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='claims' AND column_name='adjudicated_by') THEN
        ALTER TABLE claims ADD COLUMN adjudicated_by INTEGER REFERENCES users(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='claims' AND column_name='adjudicated_at') THEN
        ALTER TABLE claims ADD COLUMN adjudicated_at TIMESTAMP;
      END IF;
    END $$;
  `);

  await seedCommercial();
  await seedInsuranceClaimsDesk();
  await seedFinancePaymentsDesk();
  await seedCorporateUtilisationDesk();
  console.log('Phase 3 schema ready');
}

async function seedCommercial() {
  const corpCount = await query('SELECT COUNT(*) FROM corporates');
  if (parseInt(corpCount.rows[0].count, 10) === 0) {
    await query(`
      INSERT INTO corporates (name, industry, region, town, contact_name, contact_phone, coverage_percent, copay_amount)
      VALUES
        ('Ghana Ports Authority', 'Maritime', 'Greater Accra', 'Tema', 'Kwame Owusu', '0302005001', 60, 20),
        ('Cocoa Board Staff Scheme', 'Agriculture', 'Ashanti', 'Kumasi', 'Abena Sarpong', '0322005002', 70, 15)
    `);
    console.log('Seeded corporate accounts');
  }

  const insCount = await query('SELECT COUNT(*) FROM insurers');
  if (parseInt(insCount.rows[0].count, 10) === 0) {
    await query(`
      INSERT INTO insurers (name, plan_name, region, coverage_percent, copay_amount, annual_limit)
      VALUES
        ('Star Health Ghana', 'Outpatient Plus', 'Greater Accra', 80, 10, 5000),
        ('NHIS Partner Desk', 'NHIS Outpatient', 'National', 70, 15, 2000)
    `);
    console.log('Seeded insurers');
  }

  await ensureUser('corporate', 'corp123', 'corporate', 'GPA Benefits Desk', '0240000201');
  await ensureUser('insurance', 'insure123', 'insurance', 'Star Health Adjudicator', '0240000202');
  await ensureUser('finance', 'fin123', 'finance', 'Medilynks Finance', '0240000203');

  const patient = await query('SELECT id, staff_id FROM patients WHERE user_id IS NOT NULL ORDER BY id LIMIT 1');
  if (patient.rows[0]) {
    const corp = await query("SELECT id FROM corporates WHERE name = 'Ghana Ports Authority' LIMIT 1");
    const ins = await query("SELECT id FROM insurers WHERE name = 'Star Health Ghana' LIMIT 1");
    if (corp.rows[0]) {
      await query(
        `INSERT INTO corporate_members (corporate_id, patient_id, staff_id, department, status)
         VALUES ($1, $2, $3, 'Operations', 'active') ON CONFLICT DO NOTHING`,
        [corp.rows[0].id, patient.rows[0].id, patient.rows[0].staff_id || 'GPA-1001']
      );
    }
    if (ins.rows[0]) {
      await query(
        `INSERT INTO policies (insurer_id, patient_id, policy_number, status, ends_on)
         VALUES ($1, $2, $3, 'active', CURRENT_DATE + INTERVAL '1 year')
         ON CONFLICT (policy_number) DO NOTHING`,
        [ins.rows[0].id, patient.rows[0].id, `SHG-${patient.rows[0].id}`]
      );
    }
  }

  await seedCoverageDirectory();
}

/** Demo open claims so the insurance desk can adjudicate without waiting for a live visit. */
async function seedInsuranceClaimsDesk() {
  const open = await query(
    `SELECT COUNT(*)::int AS n FROM claims
     WHERE source = 'insurance' AND status IN ('submitted', 'queried')`
  ).catch(() => ({ rows: [{ n: 0 }] }));
  if (Number(open.rows[0]?.n || 0) > 0) return;

  const ins = await query("SELECT id, name FROM insurers WHERE name = 'Star Health Ghana' LIMIT 1");
  if (!ins.rows[0]) return;

  let policies = await query(
    `SELECT p.id AS policy_id, p.patient_id, p.policy_number, pt.full_name
     FROM policies p JOIN patients pt ON pt.id = p.patient_id
     WHERE p.insurer_id = $1 AND p.status = 'active'
     ORDER BY p.id ASC LIMIT 5`,
    [ins.rows[0].id]
  );

  if (!policies.rows[0]) {
    const patient = await query('SELECT id, full_name FROM patients ORDER BY id ASC LIMIT 1');
    if (!patient.rows[0]) return;
    const policyNumber = `SHG-DEMO-${patient.rows[0].id}`;
    await query(
      `INSERT INTO policies (insurer_id, patient_id, policy_number, status, ends_on)
       VALUES ($1, $2, $3, 'active', CURRENT_DATE + INTERVAL '1 year')
       ON CONFLICT (policy_number) DO UPDATE SET status = 'active', patient_id = EXCLUDED.patient_id`,
      [ins.rows[0].id, patient.rows[0].id, policyNumber]
    );
    policies = await query(
      `SELECT p.id AS policy_id, p.patient_id, p.policy_number, pt.full_name
       FROM policies p JOIN patients pt ON pt.id = p.patient_id
       WHERE p.insurer_id = $1 AND p.status = 'active'
       ORDER BY p.id ASC LIMIT 5`,
      [ins.rows[0].id]
    );
  }
  if (!policies.rows[0]) return;

  const apt = await query(
    `SELECT id FROM appointments WHERE patient_id = $1 ORDER BY id DESC LIMIT 1`,
    [policies.rows[0].patient_id]
  ).catch(() => ({ rows: [] as any[] }));
  const appointmentId = apt.rows[0]?.id || null;

  const demos: Array<{ amount: number; status: string; notes: string | null; patientIdx: number }> = [
    { amount: 40, status: 'submitted', notes: null, patientIdx: 0 },
    { amount: 40, status: 'submitted', notes: null, patientIdx: Math.min(1, policies.rows.length - 1) },
    {
      amount: 35,
      status: 'queried',
      notes: 'Please upload the consultation receipt from the clinic.',
      patientIdx: 0,
    },
  ];

  for (const demo of demos) {
    const pol = policies.rows[demo.patientIdx] || policies.rows[0];
    const seq = await query(`SELECT nextval('claim_code_seq') AS n`);
    const claimCode = `CLM-${String(seq.rows[0].n).padStart(6, '0')}`;
    await query(
      `INSERT INTO claims (claim_code, appointment_id, patient_id, policy_id, source, amount, status, notes)
       VALUES ($1, $2, $3, $4, 'insurance', $5, $6, $7)`,
      [claimCode, appointmentId, pol.patient_id, pol.policy_id, demo.amount, demo.status, demo.notes]
    ).catch(() => null);
  }

  const pendingPa = await query(
    `SELECT COUNT(*)::int AS n FROM preauths pa
     LEFT JOIN policies p ON p.id = pa.policy_id
     WHERE pa.status = 'pending' AND (p.insurer_id = $1 OR pa.policy_id IS NULL)`,
    [ins.rows[0].id]
  ).catch(() => ({ rows: [{ n: 0 }] }));
  if (Number(pendingPa.rows[0]?.n || 0) === 0) {
    const pol = policies.rows[0];
    const pseq = await query(`SELECT nextval('preauth_code_seq') AS n`);
    await query(
      `INSERT INTO preauths (preauth_code, appointment_id, patient_id, policy_id, service, requested_amount, status, notes)
       VALUES ($1, $2, $3, $4, 'general consultation (demo)', 120, 'pending', 'Ops demo — awaiting insurer decision')`,
      [`PA-${String(pseq.rows[0].n).padStart(6, '0')}`, appointmentId, pol.patient_id, pol.policy_id]
    ).catch(() => null);
  }

  console.log('Seeded insurance claims desk demo queue');
}

async function seedFinancePaymentsDesk() {
  const paid = await query(
    `SELECT COUNT(*)::int AS n FROM payments WHERE status IN ('paid', 'refunded')`
  ).catch(() => ({ rows: [{ n: 0 }] }));
  if (Number(paid.rows[0]?.n || 0) >= 3) return;

  const patients = await query(
    `SELECT pt.id AS patient_id, pt.full_name, pt.phone_number, pt.email,
            a.id AS appointment_id, a.appointment_id AS apt_code, a.doctor_id
     FROM patients pt
     LEFT JOIN LATERAL (
       SELECT id, appointment_id, doctor_id FROM appointments
       WHERE patient_id = pt.id ORDER BY id DESC LIMIT 1
     ) a ON true
     WHERE pt.id IS NOT NULL
     ORDER BY pt.id ASC LIMIT 4`
  ).catch(() => ({ rows: [] as any[] }));
  if (!patients.rows[0]) return;

  const demos: Array<{
    gateway: string;
    amount: number;
    covered: number;
    copay: number;
    coverage: string | null;
    reconcile: boolean;
    refund: boolean;
    refPrefix: string;
    patientIdx: number;
  }> = [
    {
      gateway: 'demo',
      amount: 120,
      covered: 0,
      copay: 120,
      coverage: null,
      reconcile: false,
      refund: false,
      refPrefix: 'digidemo_finance_',
      patientIdx: 0,
    },
    {
      gateway: 'paystack',
      amount: 20,
      covered: 100,
      copay: 20,
      coverage: 'insurance',
      reconcile: true,
      refund: false,
      refPrefix: 'digihealth_finance_',
      patientIdx: Math.min(1, patients.rows.length - 1),
    },
    {
      gateway: 'paystack',
      amount: 15,
      covered: 105,
      copay: 15,
      coverage: 'corporate',
      reconcile: false,
      refund: false,
      refPrefix: 'digihealth_finance_',
      patientIdx: Math.min(2, patients.rows.length - 1),
    },
    {
      gateway: 'demo',
      amount: 120,
      covered: 0,
      copay: 120,
      coverage: null,
      reconcile: false,
      refund: true,
      refPrefix: 'digidemo_refund_',
      patientIdx: 0,
    },
  ];

  const financeUser = await query(`SELECT id FROM users WHERE username = 'finance' LIMIT 1`);
  const reconcilerId = financeUser.rows[0]?.id || null;

  for (const demo of demos) {
    const row = patients.rows[demo.patientIdx] || patients.rows[0];
    let appointmentId = row.appointment_id as number | null;
    if (!appointmentId) {
      const aptCode = `APT-FIN-${row.patient_id}-${Date.now().toString(36).slice(-4)}`.toUpperCase();
      const created = await query(
        `INSERT INTO appointments (
           appointment_id, patient_id, full_name, phone_number, email, doctor_id,
           preferred_date, preferred_time, service, status, payment_status
         ) VALUES ($1, $2, $3, $4, $5, $6, CURRENT_DATE, '10:00', 'general consultation', 'approved', 'paid')
         RETURNING id`,
        [
          aptCode,
          row.patient_id,
          row.full_name || 'Demo Patient',
          row.phone_number || '0240000000',
          row.email || null,
          row.doctor_id || null,
        ]
      ).catch(() => ({ rows: [] as any[] }));
      appointmentId = created.rows[0]?.id || null;
    }
    if (!appointmentId) continue;

    const reference = `${demo.refPrefix}${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const status = demo.refund ? 'refunded' : 'paid';
    await query(
      `INSERT INTO payments (
         appointment_id, amount, currency, status, reference, gateway,
         coverage_source, covered_amount, copay_amount,
         reconciled_at, reconciled_by, refunded_at, refund_notes
       ) VALUES (
         $1, $2, 'GHS', $3, $4, $5,
         $6, $7, $8,
         $9, $10, $11, $12
       )
       ON CONFLICT (reference) DO NOTHING`,
      [
        appointmentId,
        demo.amount,
        status,
        reference,
        demo.gateway,
        demo.coverage,
        demo.covered,
        demo.copay,
        demo.reconcile ? new Date() : null,
        demo.reconcile ? reconcilerId : null,
        demo.refund ? new Date() : null,
        demo.refund ? 'Demo refund — patient cancelled before consult.' : null,
      ]
    ).catch(() => null);

    if (!demo.refund) {
      await query(
        `UPDATE appointments SET payment_status = 'paid', payment_ref = COALESCE(payment_ref, $1)
         WHERE id = $2 AND (payment_status IS NULL OR payment_status = 'unpaid')`,
        [reference, appointmentId]
      ).catch(() => null);
    }
  }

  console.log('Seeded finance payments / receipts demo queue');
}

/** Demo corporate claims so the benefits desk shows utilisation without a live visit. */
async function seedCorporateUtilisationDesk() {
  const existing = await query(
    `SELECT COUNT(*)::int AS n FROM claims WHERE source = 'corporate'`
  ).catch(() => ({ rows: [{ n: 0 }] }));
  if (Number(existing.rows[0]?.n || 0) >= 2) return;

  const corp = await query("SELECT id, name FROM corporates WHERE name = 'Ghana Ports Authority' LIMIT 1");
  if (!corp.rows[0]) return;

  let members = await query(
    `SELECT m.id AS member_id, m.patient_id, m.staff_id, m.department, pt.full_name
     FROM corporate_members m
     JOIN patients pt ON pt.id = m.patient_id
     WHERE m.corporate_id = $1
     ORDER BY m.id ASC LIMIT 5`,
    [corp.rows[0].id]
  );

  if (!members.rows[0]) {
    const patient = await query('SELECT id, full_name, staff_id FROM patients ORDER BY id ASC LIMIT 2');
    if (!patient.rows[0]) return;
    for (let i = 0; i < patient.rows.length; i++) {
      const p = patient.rows[i];
      await query(
        `INSERT INTO corporate_members (corporate_id, patient_id, staff_id, department, status)
         VALUES ($1, $2, $3, $4, 'active') ON CONFLICT (corporate_id, patient_id) DO NOTHING`,
        [
          corp.rows[0].id,
          p.id,
          p.staff_id || `GPA-DEMO-${p.id}`,
          i === 0 ? 'Operations' : 'Finance',
        ]
      ).catch(() => null);
    }
    members = await query(
      `SELECT m.id AS member_id, m.patient_id, m.staff_id, m.department, pt.full_name
       FROM corporate_members m
       JOIN patients pt ON pt.id = m.patient_id
       WHERE m.corporate_id = $1
       ORDER BY m.id ASC LIMIT 5`,
      [corp.rows[0].id]
    );
  }
  if (!members.rows[0]) return;

  const demos: Array<{
    amount: number;
    status: string;
    notes: string | null;
    memberIdx: number;
    copay: number;
    daysAgo: number;
  }> = [
    { amount: 30, status: 'submitted', notes: null, memberIdx: 0, copay: 20, daysAgo: 1 },
    {
      amount: 30,
      status: 'approved',
      notes: 'Scheme cover for outpatient consult',
      memberIdx: Math.min(1, members.rows.length - 1),
      copay: 20,
      daysAgo: 5,
    },
    {
      amount: 30,
      status: 'paid',
      notes: 'Settled against GPA staff medical',
      memberIdx: 0,
      copay: 20,
      daysAgo: 12,
    },
  ];

  for (const demo of demos) {
    const mem = members.rows[demo.memberIdx] || members.rows[0];
    let appointmentId: number | null = null;
    const apt = await query(
      `SELECT id FROM appointments WHERE patient_id = $1 ORDER BY id DESC LIMIT 1`,
      [mem.patient_id]
    ).catch(() => ({ rows: [] as any[] }));
    appointmentId = apt.rows[0]?.id || null;

    if (!appointmentId) {
      const aptCode = `APT-CORP-${mem.patient_id}-${Date.now().toString(36).slice(-4)}`.toUpperCase();
      const created = await query(
        `INSERT INTO appointments (
           appointment_id, patient_id, full_name, phone_number, email, doctor_id,
           preferred_date, preferred_time, service, status, payment_status
         ) VALUES ($1, $2, $3, '0240000000', null, null,
           CURRENT_DATE - ($4::int), '10:00', 'general consultation', 'completed', 'paid')
         RETURNING id`,
        [aptCode, mem.patient_id, mem.full_name || 'Staff Member', demo.daysAgo]
      ).catch(() => ({ rows: [] as any[] }));
      appointmentId = created.rows[0]?.id || null;
    }

    const seq = await query(`SELECT nextval('claim_code_seq') AS n`);
    const claimCode = `CLM-${String(seq.rows[0].n).padStart(6, '0')}`;
    const submittedAt = new Date(Date.now() - demo.daysAgo * 24 * 60 * 60 * 1000);
    await query(
      `INSERT INTO claims (
         claim_code, appointment_id, patient_id, corporate_id, source, amount, status, notes, submitted_at, paid_at
       ) VALUES ($1,$2,$3,$4,'corporate',$5,$6,$7,$8,$9)`,
      [
        claimCode,
        appointmentId,
        mem.patient_id,
        corp.rows[0].id,
        demo.amount,
        demo.status,
        demo.notes,
        submittedAt,
        demo.status === 'paid' ? submittedAt : null,
      ]
    ).catch(() => null);

    if (appointmentId) {
      const reference = `digihealth_corp_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
      await query(
        `INSERT INTO payments (
           appointment_id, amount, currency, status, reference, gateway,
           coverage_source, covered_amount, copay_amount
         ) VALUES ($1, $2, 'GHS', 'paid', $3, 'demo', 'corporate', $4, $5)
         ON CONFLICT (reference) DO NOTHING`,
        [appointmentId, demo.copay, reference, demo.amount, demo.copay]
      ).catch(() => null);
    }
  }

  console.log('Seeded corporate utilisation demo claims');
}

async function seedCoverageDirectory() {
  const count = await query('SELECT COUNT(*) FROM coverage_directory');
  if (parseInt(count.rows[0].count, 10) > 0) return;

  const star = await query("SELECT id FROM insurers WHERE name = 'Star Health Ghana' LIMIT 1");
  const nhis = await query("SELECT id FROM insurers WHERE name = 'NHIS Partner Desk' LIMIT 1");
  const gpa = await query("SELECT id FROM corporates WHERE name = 'Ghana Ports Authority' LIMIT 1");
  const cocoa = await query("SELECT id FROM corporates WHERE name = 'Cocoa Board Staff Scheme' LIMIT 1");

  const rows: Array<[string, number | null, number | null, string, string]> = [];
  if (star.rows[0]) {
    rows.push(['insurance', star.rows[0].id, null, 'DEMO-SHG-1001', 'Ama Mensah']);
    rows.push(['insurance', star.rows[0].id, null, 'DEMO-SHG-1002', 'Kofi Asante']);
  }
  if (nhis.rows[0]) {
    rows.push(['insurance', nhis.rows[0].id, null, 'DEMO-NHIS-2001', 'Efua Boateng']);
  }
  if (gpa.rows[0]) {
    rows.push(['corporate', null, gpa.rows[0].id, 'GPA-STAFF-9001', 'Yaw Oppong']);
    rows.push(['corporate', null, gpa.rows[0].id, 'GPA-STAFF-9002', 'Abena Darko']);
  }
  if (cocoa.rows[0]) {
    rows.push(['corporate', null, cocoa.rows[0].id, 'COCOA-STAFF-5001', 'Kwaku Frimpong']);
  }

  for (const [source, insurerId, corporateId, memberKey, memberName] of rows) {
    await query(
      `INSERT INTO coverage_directory (source, insurer_id, corporate_id, member_key, member_name, status)
       VALUES ($1,$2,$3,$4,$5,'eligible') ON CONFLICT DO NOTHING`,
      [source, insurerId, corporateId, memberKey, memberName]
    );
  }
  if (rows.length) console.log('Seeded claimable coverage directory for eligibility demos');
}

async function ensureUser(username: string, password: string, role: string, name: string, phone: string) {
  const existing = await query('SELECT id FROM users WHERE username = $1', [username]);
  if (existing.rows[0]) return existing.rows[0].id;
  const hashed = await bcrypt.hash(password, 10);
  const user = await query(
    'INSERT INTO users (username, password, role, name, phone_number) VALUES ($1,$2,$3,$4,$5) RETURNING id',
    [username, hashed, role, name, phone]
  );
  console.log(`Default ${role} user created (${username}/${password})`);
  return user.rows[0].id;
}

function money(v: any, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

export async function getEligibility(patientId: number) {
  const policy = await query(
    `SELECT p.*, i.name as insurer_name, i.plan_name, i.coverage_percent, i.copay_amount, i.annual_limit
     FROM policies p JOIN insurers i ON p.insurer_id = i.id
     WHERE p.patient_id = $1 AND p.status = 'active' AND i.is_active = TRUE
       AND (p.ends_on IS NULL OR p.ends_on >= CURRENT_DATE)
     ORDER BY p.id DESC LIMIT 1`,
    [patientId]
  );
  const member = await query(
    `SELECT m.*, c.name as corporate_name, c.coverage_percent, c.copay_amount, c.annual_limit
     FROM corporate_members m JOIN corporates c ON m.corporate_id = c.id
     WHERE m.patient_id = $1 AND m.status = 'active' AND c.is_active = TRUE
     ORDER BY m.id DESC LIMIT 1`,
    [patientId]
  );

  const fee = CONSULT_FEE;
  const membership = await getActiveMembership(patientId);
  const mem = membershipEligibilityOverlay(membership);

  if (policy.rows[0]) {
    const copay = money(policy.rows[0].copay_amount, 10);
    const best = mem && mem.copay < copay ? mem.copay : copay;
    const usedMembership = Boolean(mem && mem.copay < copay);
    return {
      source: usedMembership ? 'membership' : 'insurance',
      eligible: true,
      consult_fee: fee,
      copay: best,
      covered_amount: Math.max(0, fee - best),
      coverage_percent: usedMembership
        ? mem!.coverage_percent
        : money(policy.rows[0].coverage_percent, 80),
      payer_name: usedMembership ? mem!.payer_name : policy.rows[0].insurer_name,
      plan_name: usedMembership ? mem!.plan_name : policy.rows[0].plan_name,
      policy_number: usedMembership ? mem!.policy_number : policy.rows[0].policy_number,
      policy_id: usedMembership ? null : policy.rows[0].id,
      corporate_id: null,
      member: member.rows[0] || null,
      membership_tier: mem?.membership_tier || null,
    };
  }
  if (member.rows[0]) {
    const copay = money(member.rows[0].copay_amount, 20);
    const best = mem && mem.copay < copay ? mem.copay : copay;
    const usedMembership = Boolean(mem && mem.copay < copay);
    const annualLimit = money(member.rows[0].annual_limit, 3000);
    const ytd = await query(
      `SELECT COALESCE(SUM(amount),0) AS spent
       FROM claims
       WHERE corporate_id = $1 AND patient_id = $2 AND source = 'corporate'
         AND status != 'rejected'
         AND submitted_at >= date_trunc('year', CURRENT_DATE)`,
      [member.rows[0].corporate_id, patientId]
    );
    const spentYtd = money(ytd.rows[0]?.spent, 0);
    const remaining = Math.max(0, annualLimit - spentYtd);
    const desiredCovered = usedMembership
      ? Math.max(0, fee - best)
      : Math.max(0, fee - best);
    const coveredAmount = usedMembership ? desiredCovered : Math.min(desiredCovered, remaining);
    const effectiveCopay = fee - coveredAmount;
    return {
      source: usedMembership ? 'membership' : 'corporate',
      eligible: true,
      consult_fee: fee,
      copay: effectiveCopay,
      covered_amount: coveredAmount,
      coverage_percent: usedMembership
        ? mem!.coverage_percent
        : money(member.rows[0].coverage_percent, 60),
      payer_name: usedMembership ? mem!.payer_name : member.rows[0].corporate_name,
      plan_name: usedMembership ? mem!.plan_name : 'Staff medical scheme',
      policy_number: usedMembership ? mem!.policy_number : member.rows[0].staff_id,
      policy_id: null,
      corporate_id: usedMembership ? null : member.rows[0].corporate_id,
      member: member.rows[0],
      membership_tier: mem?.membership_tier || null,
      annual_limit: annualLimit,
      spent_ytd: spentYtd,
      limit_remaining: remaining,
      limit_exhausted: !usedMembership && remaining <= 0,
    };
  }
  if (mem) return mem;
  return {
    source: 'self_pay',
    eligible: false,
    consult_fee: fee,
    copay: fee,
    covered_amount: 0,
    coverage_percent: 0,
    payer_name: 'Self pay',
    plan_name: null,
    policy_number: null,
    policy_id: null,
    corporate_id: null,
    member: null,
    membership_tier: null,
  };
}

function coveragePreviewFromInsurer(insurer: any, memberKey: string, memberName?: string | null) {
  const fee = CONSULT_FEE;
  const copay = money(insurer.copay_amount, 10);
  return {
    source: 'insurance',
    eligible: true,
    consult_fee: fee,
    copay,
    covered_amount: Math.max(0, fee - copay),
    coverage_percent: money(insurer.coverage_percent, 80),
    payer_name: insurer.name,
    plan_name: insurer.plan_name,
    policy_number: memberKey,
    member_name: memberName || null,
    insurer_id: insurer.id,
    corporate_id: null,
  };
}

function coveragePreviewFromCorporate(corp: any, memberKey: string, memberName?: string | null) {
  const fee = CONSULT_FEE;
  const copay = money(corp.copay_amount, 20);
  return {
    source: 'corporate',
    eligible: true,
    consult_fee: fee,
    copay,
    covered_amount: Math.max(0, fee - copay),
    coverage_percent: money(corp.coverage_percent, 60),
    payer_name: corp.name,
    plan_name: 'Staff medical scheme',
    policy_number: memberKey,
    member_name: memberName || null,
    insurer_id: null,
    corporate_id: corp.id,
  };
}

async function lookupCoverageCheck(opts: {
  source: 'insurance' | 'corporate';
  memberKey: string;
  payerId?: number | null;
  patientId: number;
}) {
  const key = opts.memberKey.trim().toUpperCase();
  if (!key) {
    return { matched: false, eligible: false, can_attach: false, message: 'Enter a policy or staff ID.', preview: null };
  }

  if (opts.source === 'insurance') {
    const mine = await query(
      `SELECT p.*, i.name as insurer_name, i.plan_name, i.coverage_percent, i.copay_amount
       FROM policies p JOIN insurers i ON p.insurer_id = i.id
       WHERE p.patient_id = $1 AND UPPER(p.policy_number) = $2 AND p.status = 'active'
       LIMIT 1`,
      [opts.patientId, key]
    );
    if (mine.rows[0]) {
      const row = mine.rows[0];
      return {
        matched: true,
        eligible: true,
        can_attach: false,
        already_linked: true,
        message: 'This policy is already on your account.',
        preview: coveragePreviewFromInsurer(
          {
            id: row.insurer_id,
            name: row.insurer_name,
            plan_name: row.plan_name,
            coverage_percent: row.coverage_percent,
            copay_amount: row.copay_amount,
          },
          row.policy_number
        ),
      };
    }

    const taken = await query(
      `SELECT id, patient_id FROM policies WHERE UPPER(policy_number) = $1 AND status = 'active' LIMIT 1`,
      [key]
    );
    if (taken.rows[0] && taken.rows[0].patient_id !== opts.patientId) {
      return {
        matched: true,
        eligible: false,
        can_attach: false,
        message: 'This policy number is already linked to another patient.',
        preview: null,
      };
    }

    const dir = await query(
      `SELECT d.*, i.name, i.plan_name, i.coverage_percent, i.copay_amount, i.id as insurer_pk
       FROM coverage_directory d
       JOIN insurers i ON d.insurer_id = i.id
       WHERE d.source = 'insurance' AND UPPER(d.member_key) = $1
         AND i.is_active = TRUE
         AND ($2::int IS NULL OR d.insurer_id = $2)
       LIMIT 1`,
      [key, opts.payerId || null]
    );
    if (dir.rows[0]) {
      const d = dir.rows[0];
      if (d.status === 'claimed' && d.claimed_patient_id && d.claimed_patient_id !== opts.patientId) {
        return {
          matched: true,
          eligible: false,
          can_attach: false,
          message: 'This policy was already claimed by another member.',
          preview: null,
        };
      }
      const alreadyMine = d.claimed_patient_id === opts.patientId;
      return {
        matched: true,
        eligible: true,
        can_attach: !alreadyMine,
        already_linked: alreadyMine,
        message: alreadyMine
          ? 'Covered — this policy is on your chart.'
          : 'Eligible — attach this insurance to use the copay on booking and Consult Now.',
        preview: coveragePreviewFromInsurer(
          {
            id: d.insurer_pk,
            name: d.name,
            plan_name: d.plan_name,
            coverage_percent: d.coverage_percent,
            copay_amount: d.copay_amount,
          },
          d.member_key,
          d.member_name
        ),
        directory_id: d.id,
      };
    }

    return {
      matched: false,
      eligible: false,
      can_attach: false,
      message: 'No active insurance match for that policy number.',
      preview: null,
    };
  }

  const mineCorp = await query(
    `SELECT m.*, c.name as corporate_name, c.coverage_percent, c.copay_amount
     FROM corporate_members m JOIN corporates c ON m.corporate_id = c.id
     WHERE m.patient_id = $1 AND UPPER(COALESCE(m.staff_id,'')) = $2 AND m.status = 'active'
     LIMIT 1`,
    [opts.patientId, key]
  );
  if (mineCorp.rows[0]) {
    const row = mineCorp.rows[0];
    return {
      matched: true,
      eligible: true,
      can_attach: false,
      already_linked: true,
      message: 'This staff ID is already on your corporate scheme.',
      preview: coveragePreviewFromCorporate(
        {
          id: row.corporate_id,
          name: row.corporate_name,
          coverage_percent: row.coverage_percent,
          copay_amount: row.copay_amount,
        },
        row.staff_id
      ),
    };
  }

  const dir = await query(
    `SELECT d.*, c.name, c.coverage_percent, c.copay_amount, c.id as corporate_pk
     FROM coverage_directory d
     JOIN corporates c ON d.corporate_id = c.id
     WHERE d.source = 'corporate' AND UPPER(d.member_key) = $1
       AND c.is_active = TRUE
       AND ($2::int IS NULL OR d.corporate_id = $2)
     LIMIT 1`,
    [key, opts.payerId || null]
  );
  if (dir.rows[0]) {
    const d = dir.rows[0];
    if (d.status === 'claimed' && d.claimed_patient_id && d.claimed_patient_id !== opts.patientId) {
      return {
        matched: true,
        eligible: false,
        can_attach: false,
        message: 'This staff ID was already claimed by another employee.',
        preview: null,
      };
    }
    const alreadyMine = d.claimed_patient_id === opts.patientId;
    return {
      matched: true,
      eligible: true,
      can_attach: !alreadyMine,
      already_linked: alreadyMine,
      message: alreadyMine
        ? 'Covered — corporate scheme is on your chart.'
        : 'Eligible — attach this corporate scheme to lower your consult copay.',
      preview: coveragePreviewFromCorporate(
        {
          id: d.corporate_pk,
          name: d.name,
          coverage_percent: d.coverage_percent,
          copay_amount: d.copay_amount,
        },
        d.member_key,
        d.member_name
      ),
      directory_id: d.id,
    };
  }

  return {
    matched: false,
    eligible: false,
    can_attach: false,
    message: 'No active corporate match for that staff ID.',
    preview: null,
  };
}

async function attachCoverageFromDirectory(patientId: number, check: Awaited<ReturnType<typeof lookupCoverageCheck>>) {
  if (!check.can_attach || !check.preview) {
    throw Object.assign(new Error(check.message || 'Cannot attach'), { status: 400 });
  }
  const preview = check.preview;
  const key = String(preview.policy_number || '').trim();

  if (preview.source === 'insurance') {
    await query(
      `UPDATE policies SET status = 'inactive' WHERE patient_id = $1 AND status = 'active'`,
      [patientId]
    );
    const existing = await query(
      'SELECT id, patient_id, status FROM policies WHERE UPPER(policy_number) = $1 LIMIT 1',
      [key.toUpperCase()]
    );
    if (existing.rows[0]) {
      const ownerId = existing.rows[0].patient_id == null ? null : Number(existing.rows[0].patient_id);
      if (ownerId != null && ownerId !== patientId) {
        throw Object.assign(
          new Error('This policy number belongs to another patient and cannot be attached.'),
          { status: 409 }
        );
      }
      await query(
        `UPDATE policies SET patient_id = $1, insurer_id = $2, status = 'active',
           ends_on = CURRENT_DATE + INTERVAL '1 year'
         WHERE id = $3`,
        [patientId, preview.insurer_id, existing.rows[0].id]
      );
    } else {
      await query(
        `INSERT INTO policies (insurer_id, patient_id, policy_number, status, ends_on)
         VALUES ($1,$2,$3,'active', CURRENT_DATE + INTERVAL '1 year')`,
        [preview.insurer_id, patientId, key]
      );
    }
  } else {
    await query(
      `INSERT INTO corporate_members (corporate_id, patient_id, staff_id, department, status)
       VALUES ($1,$2,$3,'Self-enrolled','active')
       ON CONFLICT (corporate_id, patient_id) DO UPDATE
         SET status = 'active', staff_id = EXCLUDED.staff_id`,
      [preview.corporate_id, patientId, key]
    );
  }

  if ((check as any).directory_id) {
    await query(
      `UPDATE coverage_directory
       SET status = 'claimed', claimed_patient_id = $1
       WHERE id = $2`,
      [patientId, (check as any).directory_id]
    );
  }

  return getEligibility(patientId);
}

export async function recordVisitPayment(
  appointmentId: number,
  patientId: number | null,
  doctorUserId: number | null,
  paymentRef?: string,
  gateway = 'paystack'
) {
  const elig = patientId ? await getEligibility(patientId) : await getEligibility(0);
  const ref = paymentRef || 'PAY-' + Math.random().toString(36).substring(2, 10).toUpperCase();
  const existing = await query('SELECT id FROM payments WHERE reference = $1 LIMIT 1', [ref]);
  if (existing.rows[0]) {
    return { paymentRef: ref, eligibility: elig, alreadyProcessed: true };
  }
  await query(
    `INSERT INTO payments (appointment_id, amount, currency, status, reference, gateway, coverage_source, covered_amount, copay_amount)
     VALUES ($1, $2, 'GHS', 'paid', $3, $4, $5, $6, $7)`,
    [appointmentId, elig.copay, ref, gateway, elig.source, elig.covered_amount, elig.copay]
  );

  if (elig.covered_amount > 0 && patientId) {
    const seq = await query(`SELECT nextval('claim_code_seq') AS n`);
    const claimCode = `CLM-${String(seq.rows[0].n).padStart(6, '0')}`;
    await query(
      `INSERT INTO claims (claim_code, appointment_id, patient_id, policy_id, corporate_id, source, amount, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'submitted')`,
      [claimCode, appointmentId, patientId, elig.policy_id, elig.corporate_id, elig.source, elig.covered_amount]
    );
    const pseq = await query(`SELECT nextval('preauth_code_seq') AS n`);
    await query(
      `INSERT INTO preauths (preauth_code, appointment_id, patient_id, policy_id, corporate_id, service, requested_amount, approved_amount, status, notes, decided_at)
       VALUES ($1,$2,$3,$4,$5,'general consultation',$6,$7,'approved','Auto-approved on copay collection', CURRENT_TIMESTAMP)`,
      [
        `PA-${String(pseq.rows[0].n).padStart(6, '0')}`,
        appointmentId,
        patientId,
        elig.policy_id,
        elig.corporate_id,
        CONSULT_FEE,
        elig.covered_amount,
      ]
    );
  }

  if (doctorUserId) {
    await query(
      `INSERT INTO doctor_earnings (doctor_user_id, appointment_id, amount, status)
       VALUES ($1,$2,$3,'accrued') ON CONFLICT (appointment_id) DO NOTHING`,
      [doctorUserId, appointmentId, DOCTOR_SHARE]
    );
  }

  return { paymentRef: ref, eligibility: elig };
}

async function notifyUser(
  deps: Pick<Deps, 'sendPushNotification'>,
  userId: number | null | undefined,
  title: string,
  message: string,
  type = 'billing'
) {
  if (!userId) return;
  await query(
    'INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, $4)',
    [userId, title, message, type]
  );
  await deps.sendPushNotification([userId], title, message, { type });
}

export function registerPhase3Routes(app: Express, deps: Deps) {
  const { authenticate } = deps;

  app.get('/api/billing/eligibility', authenticate, async (req: AuthedRequest, res) => {
    try {
      let patientId = req.query.patient_id ? Number(req.query.patient_id) : null;
      if (!patientId) {
        const patient = await getPatientForUser(req.user!.id);
        patientId = patient?.id || null;
      }
      if (!patientId) return res.json(await getEligibility(0));
      res.json(await getEligibility(patientId));
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/billing/payers', authenticate, async (req: AuthedRequest, res) => {
    try {
      const [insurers, corporates] = await Promise.all([
        query(
          `SELECT id, name, plan_name, coverage_percent, copay_amount, region
           FROM insurers WHERE is_active = TRUE ORDER BY name`
        ),
        query(
          `SELECT id, name, industry, coverage_percent, copay_amount, region, town
           FROM corporates WHERE is_active = TRUE ORDER BY name`
        ),
      ]);
      res.json({
        insurers: insurers.rows,
        corporates: corporates.rows,
        demo_hints: [
          { source: 'insurance', member_key: 'DEMO-SHG-1001', label: 'Star Health demo policy' },
          { source: 'insurance', member_key: 'DEMO-NHIS-2001', label: 'NHIS demo policy' },
          { source: 'corporate', member_key: 'GPA-STAFF-9001', label: 'GPA staff ID' },
          { source: 'corporate', member_key: 'COCOA-STAFF-5001', label: 'Cocoa Board staff ID' },
        ],
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/billing/eligibility/check', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient?.id) return res.status(400).json({ message: 'Patient profile required' });

      const source = String(req.body.source || 'insurance').toLowerCase();
      if (source !== 'insurance' && source !== 'corporate') {
        return res.status(400).json({ message: 'source must be insurance or corporate' });
      }
      const memberKey = String(req.body.member_key || req.body.policy_number || req.body.staff_id || '').trim();
      const payerId = req.body.payer_id ? Number(req.body.payer_id) : null;

      const check = await lookupCoverageCheck({
        source: source as 'insurance' | 'corporate',
        memberKey,
        payerId,
        patientId: patient.id,
      });
      const current = await getEligibility(patient.id);
      res.json({ ...check, current });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/billing/coverage/attach', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient?.id) return res.status(400).json({ message: 'Patient profile required' });

      const source = String(req.body.source || 'insurance').toLowerCase();
      if (source !== 'insurance' && source !== 'corporate') {
        return res.status(400).json({ message: 'source must be insurance or corporate' });
      }
      const memberKey = String(req.body.member_key || req.body.policy_number || req.body.staff_id || '').trim();
      const payerId = req.body.payer_id ? Number(req.body.payer_id) : null;

      const check = await lookupCoverageCheck({
        source: source as 'insurance' | 'corporate',
        memberKey,
        payerId,
        patientId: patient.id,
      });

      if (!check.can_attach) {
        return res.status(400).json({ message: check.message || 'Cannot attach this cover', check });
      }

      const eligibility = await attachCoverageFromDirectory(patient.id, check);
      await notifyUser(
        deps,
        req.user!.id,
        'Cover attached',
        eligibility.eligible
          ? `${eligibility.payer_name} · copay GHS ${eligibility.copay} applies to your next visit`
          : 'Coverage updated',
        'billing'
      );
      res.json({
        message: 'Coverage attached',
        eligibility,
        preview: check.preview,
      });
    } catch (err: any) {
      console.error(err);
      res.status(err.status || 500).json({ message: err.message || 'Server error' });
    }
  });

  app.get('/api/corporate/dashboard', authenticate, async (req: AuthedRequest, res) => {
    if (!['corporate', 'admin', 'finance'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const scopedId =
        req.user!.role === 'corporate' ? await commercialOrgId('corporate', req.user!.id) : null;
      const corp = scopedId
        ? await query('SELECT * FROM corporates WHERE id = $1', [scopedId])
        : await query('SELECT * FROM corporates ORDER BY id');
      const corpIds = corp.rows.map((c: { id: number }) => c.id);
      if (req.user!.role === 'corporate' && !scopedId) {
        return res.json({
          corporate: null,
          members: [],
          utilisation: [],
          by_department: [],
          billed: { billed: 0, claims: 0 },
          stats: {
            members_active: 0,
            members_suspended: 0,
            members_total: 0,
            billed_ytd: 0,
            claims_open: 0,
            claims_approved: 0,
            claims_paid: 0,
            claims_rejected: 0,
            annual_limit: 0,
            limit_remaining: 0,
            copay_collected: 0,
          },
        });
      }
      const members = corpIds.length
        ? await query(
            `SELECT m.*, p.full_name, p.patient_code, p.phone_number
             FROM corporate_members m JOIN patients p ON m.patient_id = p.id
             WHERE m.corporate_id = ANY($1)
             ORDER BY m.enrolled_at DESC`,
            [corpIds]
          )
        : { rows: [] as any[] };
      const spend = corpIds.length
        ? await query(
            `SELECT COALESCE(SUM(amount),0) AS billed, COUNT(*) AS claims
             FROM claims WHERE source = 'corporate' AND status != 'rejected'
               AND corporate_id = ANY($1)`,
            [corpIds]
          )
        : { rows: [{ billed: 0, claims: 0 }] };

      const utilisation = corpIds.length
        ? await query(
            `SELECT c.id, c.claim_code, c.amount, c.status, c.notes,
                    c.submitted_at, c.paid_at, c.appointment_id,
                    a.appointment_id AS apt_code,
                    pt.full_name, pt.patient_code,
                    m.staff_id, m.department,
                    pay.copay_amount, pay.covered_amount, pay.reference AS payment_ref, pay.gateway
             FROM claims c
             JOIN patients pt ON pt.id = c.patient_id
             LEFT JOIN corporate_members m
               ON m.patient_id = c.patient_id AND m.corporate_id = c.corporate_id
             LEFT JOIN appointments a ON a.id = c.appointment_id
             LEFT JOIN LATERAL (
               SELECT copay_amount, covered_amount, reference, gateway
               FROM payments
               WHERE appointment_id = c.appointment_id
                 AND (coverage_source = 'corporate' OR coverage_source IS NULL)
               ORDER BY id DESC LIMIT 1
             ) pay ON true
             WHERE c.source = 'corporate' AND c.corporate_id = ANY($1)
             ORDER BY c.submitted_at DESC NULLS LAST, c.id DESC
             LIMIT 100`,
            [corpIds]
          )
        : { rows: [] as any[] };

      const byDept = corpIds.length
        ? await query(
            `SELECT COALESCE(NULLIF(TRIM(m.department), ''), 'Unassigned') AS department,
                    COUNT(*)::int AS visits,
                    COALESCE(SUM(c.amount),0) AS billed
             FROM claims c
             LEFT JOIN corporate_members m
               ON m.patient_id = c.patient_id AND m.corporate_id = c.corporate_id
             WHERE c.source = 'corporate' AND c.status != 'rejected'
               AND c.corporate_id = ANY($1)
               AND c.submitted_at >= date_trunc('year', CURRENT_DATE)
             GROUP BY 1
             ORDER BY billed DESC`,
            [corpIds]
          )
        : { rows: [] as any[] };

      const primary = corp.rows[0] || null;
      const annualLimit = money(primary?.annual_limit, 3000);
      const statsRow = corpIds.length
        ? await query(
            `SELECT
               (SELECT COUNT(*)::int FROM corporate_members WHERE corporate_id = ANY($1) AND status = 'active') AS members_active,
               (SELECT COUNT(*)::int FROM corporate_members WHERE corporate_id = ANY($1) AND status = 'suspended') AS members_suspended,
               (SELECT COUNT(*)::int FROM corporate_members WHERE corporate_id = ANY($1)) AS members_total,
               (SELECT COALESCE(SUM(amount),0) FROM claims
                 WHERE source = 'corporate' AND status != 'rejected' AND corporate_id = ANY($1)
                   AND submitted_at >= date_trunc('year', CURRENT_DATE)) AS billed_ytd,
               (SELECT COUNT(*)::int FROM claims
                 WHERE source = 'corporate' AND corporate_id = ANY($1) AND status IN ('submitted','queried')) AS claims_open,
               (SELECT COUNT(*)::int FROM claims
                 WHERE source = 'corporate' AND corporate_id = ANY($1) AND status = 'approved') AS claims_approved,
               (SELECT COUNT(*)::int FROM claims
                 WHERE source = 'corporate' AND corporate_id = ANY($1) AND status = 'paid') AS claims_paid,
               (SELECT COUNT(*)::int FROM claims
                 WHERE source = 'corporate' AND corporate_id = ANY($1) AND status = 'rejected') AS claims_rejected,
               (SELECT COALESCE(SUM(copay_amount),0) FROM payments pay
                 JOIN appointments a ON a.id = pay.appointment_id
                 JOIN corporate_members m ON m.patient_id = a.patient_id AND m.corporate_id = ANY($1)
                 WHERE pay.coverage_source = 'corporate' AND pay.status = 'paid') AS copay_collected`,
            [corpIds]
          )
        : {
            rows: [
              {
                members_active: 0,
                members_suspended: 0,
                members_total: 0,
                billed_ytd: 0,
                claims_open: 0,
                claims_approved: 0,
                claims_paid: 0,
                claims_rejected: 0,
                copay_collected: 0,
              },
            ],
          };

      const billedYtd = money(statsRow.rows[0]?.billed_ytd, 0);
      res.json({
        corporate: primary,
        corporates: corp.rows,
        members: members.rows,
        utilisation: utilisation.rows,
        by_department: byDept.rows,
        billed: spend.rows[0],
        stats: {
          ...statsRow.rows[0],
          annual_limit: annualLimit,
          limit_remaining: Math.max(0, annualLimit - billedYtd),
        },
        note: 'Staff roster and visit utilisation — claim amounts only, no clinical notes.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/corporate/members', authenticate, async (req: AuthedRequest, res) => {
    if (!['corporate', 'admin'].includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const { patient_code, staff_id, department } = req.body;
      const patient = await query('SELECT * FROM patients WHERE patient_code = $1 OR staff_id = $1 LIMIT 1', [patient_code]);
      if (!patient.rows[0]) return res.status(404).json({ message: 'Patient not found' });
      const scopedId =
        req.user!.role === 'corporate'
          ? await commercialOrgId('corporate', req.user!.id)
          : null;
      const corp = scopedId
        ? await query('SELECT id FROM corporates WHERE id = $1', [scopedId])
        : await query('SELECT id FROM corporates ORDER BY id LIMIT 1');
      if (!corp.rows[0]) return res.status(400).json({ message: 'No corporate account' });
      const row = await query(
        `INSERT INTO corporate_members (corporate_id, patient_id, staff_id, department, status)
         VALUES ($1,$2,$3,$4,'active')
         ON CONFLICT (corporate_id, patient_id) DO UPDATE SET status='active', staff_id=EXCLUDED.staff_id, department=EXCLUDED.department
         RETURNING *`,
        [corp.rows[0].id, patient.rows[0].id, staff_id || patient.rows[0].staff_id, department || patient.rows[0].department]
      );
      res.status(201).json(row.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/corporate/members/:id', authenticate, async (req: AuthedRequest, res) => {
    if (!['corporate', 'admin'].includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const status = typeof req.body.status === 'string' ? req.body.status.trim().toLowerCase() : null;
      if (status && !['active', 'suspended'].includes(status)) {
        return res.status(400).json({ message: 'status must be active or suspended' });
      }
      const scopedId =
        req.user!.role === 'corporate' ? await commercialOrgId('corporate', req.user!.id) : null;
      const result = scopedId
        ? await query(
            `UPDATE corporate_members SET status = COALESCE($1, status)
             WHERE id = $2 AND corporate_id = $3 RETURNING *`,
            [status, req.params.id, scopedId]
          )
        : await query(
            `UPDATE corporate_members SET status = COALESCE($1, status) WHERE id = $2 RETURNING *`,
            [status, req.params.id]
          );
      if (!result.rows[0]) return res.status(404).json({ message: 'Member not found' });
      res.json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/insurance/workbench', authenticate, async (req: AuthedRequest, res) => {
    if (!['insurance', 'admin', 'finance'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const scopedId =
        req.user!.role === 'insurance' ? await commercialOrgId('insurer', req.user!.id) : null;
      if (req.user!.role === 'insurance' && !scopedId) {
        return res.json({
          insurer: null,
          policies: [],
          preauths: [],
          claims: [],
          stats: {
            open_claims: 0,
            queried_claims: 0,
            approved_claims: 0,
            paid_claims: 0,
            rejected_claims: 0,
            pending_preauths: 0,
            policies_active: 0,
          },
          note: 'No insurer linked to this account. Ask admin to map org_accounts.',
        });
      }
      const insurer = scopedId
        ? await query('SELECT * FROM insurers WHERE id = $1', [scopedId])
        : await query('SELECT * FROM insurers ORDER BY id');
      const insIds = insurer.rows.map((i: { id: number }) => i.id);
      const [policies, preauths, claims, stats] = await Promise.all([
        insIds.length
          ? query(
              `SELECT p.*, i.name as insurer_name, pt.full_name, pt.patient_code
               FROM policies p JOIN insurers i ON p.insurer_id = i.id
               JOIN patients pt ON p.patient_id = pt.id
               WHERE p.insurer_id = ANY($1)
               ORDER BY p.created_at DESC`,
              [insIds]
            )
          : Promise.resolve({ rows: [] as any[] }),
        insIds.length
          ? query(
              `SELECT pa.*, pt.full_name, pt.patient_code, pt.phone_number,
                      pol.policy_number, a.appointment_id as apt_code
               FROM preauths pa
               JOIN patients pt ON pa.patient_id = pt.id
               LEFT JOIN policies pol ON pa.policy_id = pol.id
               LEFT JOIN appointments a ON pa.appointment_id = a.id
               WHERE pa.policy_id IS NOT NULL AND pol.insurer_id = ANY($1)
               ORDER BY
                 CASE pa.status WHEN 'pending' THEN 0 ELSE 1 END,
                 pa.created_at DESC
               LIMIT 80`,
              [insIds]
            )
          : Promise.resolve({ rows: [] as any[] }),
        insIds.length
          ? query(
              `SELECT c.*, pt.full_name, pt.patient_code, pt.phone_number,
                      pol.policy_number, i.name as insurer_name, a.appointment_id as apt_code,
                      adj.name as adjudicator_name
               FROM claims c
               JOIN patients pt ON c.patient_id = pt.id
               LEFT JOIN policies pol ON c.policy_id = pol.id
               LEFT JOIN insurers i ON pol.insurer_id = i.id
               LEFT JOIN appointments a ON c.appointment_id = a.id
               LEFT JOIN users adj ON c.adjudicated_by = adj.id
               WHERE c.source = 'insurance'
                 AND (pol.insurer_id = ANY($1) OR (c.policy_id IS NULL AND $2::boolean))
               ORDER BY
                 CASE c.status
                   WHEN 'submitted' THEN 0
                   WHEN 'queried' THEN 1
                   WHEN 'approved' THEN 2
                   ELSE 3
                 END,
                 c.submitted_at DESC
               LIMIT 100`,
              [insIds, req.user!.role === 'admin']
            )
          : Promise.resolve({ rows: [] as any[] }),
        insIds.length
          ? query(
              `SELECT
                 (SELECT COUNT(*)::int FROM claims c
                    LEFT JOIN policies pol ON c.policy_id = pol.id
                  WHERE c.source = 'insurance' AND c.status = 'submitted'
                    AND pol.insurer_id = ANY($1)) AS open_claims,
                 (SELECT COUNT(*)::int FROM claims c
                    LEFT JOIN policies pol ON c.policy_id = pol.id
                  WHERE c.source = 'insurance' AND c.status = 'queried'
                    AND pol.insurer_id = ANY($1)) AS queried_claims,
                 (SELECT COUNT(*)::int FROM claims c
                    LEFT JOIN policies pol ON c.policy_id = pol.id
                  WHERE c.source = 'insurance' AND c.status = 'approved'
                    AND pol.insurer_id = ANY($1)) AS approved_claims,
                 (SELECT COUNT(*)::int FROM claims c
                    LEFT JOIN policies pol ON c.policy_id = pol.id
                  WHERE c.source = 'insurance' AND c.status = 'paid'
                    AND pol.insurer_id = ANY($1)) AS paid_claims,
                 (SELECT COUNT(*)::int FROM claims c
                    LEFT JOIN policies pol ON c.policy_id = pol.id
                  WHERE c.source = 'insurance' AND c.status = 'rejected'
                    AND pol.insurer_id = ANY($1)) AS rejected_claims,
                 (SELECT COUNT(*)::int FROM preauths pa
                    LEFT JOIN policies pol ON pa.policy_id = pol.id
                  WHERE pa.status = 'pending' AND pol.insurer_id = ANY($1)) AS pending_preauths,
                 (SELECT COUNT(*)::int FROM policies WHERE insurer_id = ANY($1) AND status = 'active') AS policies_active`,
              [insIds]
            )
          : Promise.resolve({
              rows: [
                {
                  open_claims: 0,
                  queried_claims: 0,
                  approved_claims: 0,
                  paid_claims: 0,
                  rejected_claims: 0,
                  pending_preauths: 0,
                  policies_active: 0,
                },
              ],
            }),
      ]);
      res.json({
        insurer: insurer.rows[0] || null,
        insurers: insurer.rows,
        policies: policies.rows,
        preauths: preauths.rows,
        claims: claims.rows,
        stats: stats.rows[0] || {},
        note: 'Adjudicate claims: approve, query the patient for documents, deny, or mark paid. Patients are notified on each decision.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/insurance/preauths/:id', authenticate, async (req: AuthedRequest, res) => {
    if (!['insurance', 'admin'].includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const { status, approved_amount, notes } = req.body;
      const allowed = ['pending', 'approved', 'denied'];
      if (status && !allowed.includes(status)) return res.status(400).json({ message: 'Invalid status' });

      const scopedId =
        req.user!.role === 'insurance' ? await commercialOrgId('insurer', req.user!.id) : null;
      if (req.user!.role === 'insurance' && scopedId) {
        const owned = await query(
          `SELECT pa.id FROM preauths pa
           JOIN policies pol ON pa.policy_id = pol.id
           WHERE pa.id = $1 AND pol.insurer_id = $2`,
          [req.params.id, scopedId]
        );
        if (!owned.rows[0]) return res.status(404).json({ message: 'Preauth not found for your insurer' });
      }

      const result = await query(
        `UPDATE preauths SET
           status = COALESCE($1, status),
           approved_amount = COALESCE($2, approved_amount),
           notes = COALESCE($3, notes),
           decided_at = CURRENT_TIMESTAMP,
           decided_by = $4
         WHERE id = $5 RETURNING *`,
        [status || null, approved_amount ?? null, notes || null, req.user!.id, req.params.id]
      );
      const row = result.rows[0];
      if (row?.patient_id && status && status !== 'pending') {
        const p = await query('SELECT user_id FROM patients WHERE id = $1', [row.patient_id]);
        const title =
          status === 'approved' ? 'Preauth approved' : status === 'denied' ? 'Preauth denied' : 'Preauth updated';
        const body =
          status === 'approved'
            ? `${row.preauth_code} approved for GHS ${row.approved_amount ?? row.requested_amount}.`
            : status === 'denied'
              ? `${row.preauth_code} was denied.${notes ? ` ${notes}` : ''}`
              : `${row.preauth_code} updated.`;
        await notifyUser(deps, p.rows[0]?.user_id, title, body, 'billing');
      }
      res.json(row);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/insurance/claims/:id', authenticate, async (req: AuthedRequest, res) => {
    if (!['insurance', 'admin', 'finance', 'corporate'].includes(req.user!.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    try {
      const { status, notes } = req.body;
      const allowed = ['submitted', 'queried', 'approved', 'paid', 'rejected'];
      if (status && !allowed.includes(status)) return res.status(400).json({ message: 'Invalid status' });

      const scopedId =
        req.user!.role === 'insurance' ? await commercialOrgId('insurer', req.user!.id) : null;
      if (req.user!.role === 'insurance' && scopedId) {
        const owned = await query(
          `SELECT c.id FROM claims c
           LEFT JOIN policies pol ON c.policy_id = pol.id
           WHERE c.id = $1 AND c.source = 'insurance' AND pol.insurer_id = $2`,
          [req.params.id, scopedId]
        );
        if (!owned.rows[0]) return res.status(404).json({ message: 'Claim not found for your insurer' });
      }

      const result = await query(
        `UPDATE claims SET
           status = COALESCE($1, status),
           notes = COALESCE($2, notes),
           paid_at = CASE WHEN $1 = 'paid' THEN CURRENT_TIMESTAMP ELSE paid_at END,
           adjudicated_by = CASE
             WHEN $1 IN ('queried', 'approved', 'rejected', 'paid') THEN $3
             ELSE adjudicated_by
           END,
           adjudicated_at = CASE
             WHEN $1 IN ('queried', 'approved', 'rejected', 'paid') THEN CURRENT_TIMESTAMP
             ELSE adjudicated_at
           END
         WHERE id = $4 RETURNING *`,
        [status || null, notes || null, req.user!.id, req.params.id]
      );
      const row = result.rows[0];
      if (row?.patient_id && status) {
        const p = await query('SELECT user_id FROM patients WHERE id = $1', [row.patient_id]);
        let title: string | null = null;
        let body: string | null = null;
        if (status === 'approved') {
          title = 'Claim approved';
          body = `${row.claim_code} for GHS ${row.amount} was approved and awaits settlement.`;
        } else if (status === 'rejected') {
          title = 'Claim denied';
          body = `${row.claim_code} was denied.${notes ? ` ${notes}` : ''}`;
        } else if (status === 'queried') {
          title = 'Claim needs information';
          body = `${row.claim_code}: insurer requested more details.${notes ? ` ${notes}` : ' Reply via the clinic with supporting documents.'}`;
        } else if (status === 'paid') {
          title = 'Claim paid';
          body = `${row.claim_code} of GHS ${row.amount} was settled.`;
        } else if (status === 'submitted') {
          title = 'Claim updated';
          body = `${row.claim_code} is back in the open queue.`;
        }
        if (title && body) {
          await notifyUser(deps, p.rows[0]?.user_id, title, body, 'billing');
        }
      }
      res.json(row);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/finance/dashboard', authenticate, async (req: AuthedRequest, res) => {
    if (!['finance', 'admin'].includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const stats = await query(`
        SELECT
          (SELECT COALESCE(SUM(copay_amount),0) FROM payments WHERE status = 'paid') AS copay_collected,
          (SELECT COALESCE(SUM(covered_amount),0) FROM payments WHERE status = 'paid') AS covered_billed,
          (SELECT COALESCE(SUM(amount),0) FROM doctor_earnings WHERE status = 'accrued') AS doctor_pay_due,
          (SELECT COALESCE(SUM(amount),0) FROM doctor_earnings WHERE status = 'settled') AS doctor_pay_settled,
          (SELECT COALESCE(SUM(amount),0) FROM settlements WHERE status = 'pending') AS partner_pay_due,
          (SELECT COALESCE(SUM(amount),0) FROM claims WHERE status = 'submitted') AS open_claims,
          (SELECT COUNT(*)::int FROM payments WHERE status = 'paid' AND reconciled_at IS NULL) AS unreconciled_receipts,
          (SELECT COUNT(*)::int FROM payments WHERE status = 'paid' AND reconciled_at IS NOT NULL) AS reconciled_receipts,
          (SELECT COUNT(*)::int FROM payments WHERE status = 'refunded') AS refunded_receipts,
          (SELECT COALESCE(SUM(copay_amount),0) FROM payments WHERE status = 'paid' AND gateway = 'demo') AS demo_collected,
          (SELECT COALESCE(SUM(copay_amount),0) FROM payments WHERE status = 'paid' AND gateway = 'paystack') AS paystack_collected
      `);
      const earnings = await query(
        `SELECT e.*, u.name as doctor_name, a.appointment_id as apt_code
         FROM doctor_earnings e
         JOIN users u ON e.doctor_user_id = u.id
         LEFT JOIN appointments a ON e.appointment_id = a.id
         ORDER BY e.created_at DESC LIMIT 50`
      );
      const settlements = await query('SELECT * FROM settlements ORDER BY created_at DESC LIMIT 50');
      const claims = await query(
        `SELECT c.*, pt.full_name FROM claims c JOIN patients pt ON c.patient_id = pt.id ORDER BY c.submitted_at DESC LIMIT 50`
      );
      const payments = await query(
        `SELECT p.*,
                a.appointment_id AS apt_code,
                a.preferred_date,
                a.preferred_time,
                a.service,
                a.payment_status AS visit_payment_status,
                COALESCE(pt.full_name, a.full_name) AS patient_name,
                pt.phone_number AS patient_phone,
                ru.name AS reconciled_by_name
         FROM payments p
         LEFT JOIN appointments a ON a.id = p.appointment_id
         LEFT JOIN patients pt ON pt.id = a.patient_id
         LEFT JOIN users ru ON ru.id = p.reconciled_by
         ORDER BY p.created_at DESC
         LIMIT 100`
      );
      res.json({
        stats: stats.rows[0],
        earnings: earnings.rows,
        settlements: settlements.rows,
        claims: claims.rows,
        payments: payments.rows,
        note:
          'Reconcile paid visit receipts against bank/MoMo statements. Demo gateway rows never hit Paystack; live Paystack refunds call the Paystack refund API when keys are configured.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/finance/payments/:id', authenticate, async (req: AuthedRequest, res) => {
    if (!['finance', 'admin'].includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const id = Number(req.params.id);
      if (!Number.isFinite(id) || id <= 0) return res.status(400).json({ message: 'Invalid payment id' });

      const existing = await query('SELECT * FROM payments WHERE id = $1 LIMIT 1', [id]);
      const payment = existing.rows[0];
      if (!payment) return res.status(404).json({ message: 'Payment not found' });

      const action = String(req.body.action || '').trim().toLowerCase();
      const notes = req.body.notes != null ? String(req.body.notes).trim() : null;

      if (action === 'reconcile') {
        if (payment.status !== 'paid') {
          return res.status(400).json({ message: 'Only paid receipts can be reconciled' });
        }
        const result = await query(
          `UPDATE payments SET reconciled_at = CURRENT_TIMESTAMP, reconciled_by = $1
           WHERE id = $2 RETURNING *`,
          [req.user!.id, id]
        );
        return res.json(result.rows[0]);
      }

      if (action === 'unreconcile') {
        const result = await query(
          `UPDATE payments SET reconciled_at = NULL, reconciled_by = NULL
           WHERE id = $1 RETURNING *`,
          [id]
        );
        return res.json(result.rows[0]);
      }

      if (action === 'refund') {
        if (payment.status === 'refunded') {
          return res.status(400).json({ message: 'Payment already refunded' });
        }
        if (payment.status !== 'paid') {
          return res.status(400).json({ message: 'Only paid receipts can be refunded' });
        }

        const gateway = String(payment.gateway || '').toLowerCase();
        const reference = String(payment.reference || '');
        let refundChannel = gateway || 'local';

        if (gateway === 'paystack' && reference && !isDemoPaymentReference(reference)) {
          try {
            await refundPaystackTransaction(reference, Number(payment.copay_amount || payment.amount));
            refundChannel = 'paystack';
          } catch (err: any) {
            // Keep desk usable: still mark locally when Paystack declines (e.g. seed digihealth_ refs).
            refundChannel = 'local';
            console.warn('Paystack refund skipped:', err?.message || err);
          }
        }

        const refundNotes =
          notes ||
          (refundChannel === 'paystack'
            ? 'Refunded via Paystack'
            : gateway === 'demo' || isDemoPaymentReference(reference)
              ? 'Demo refund recorded locally'
              : 'Refund marked locally (gateway settle offline)');

        const result = await query(
          `UPDATE payments SET
             status = 'refunded',
             refunded_at = CURRENT_TIMESTAMP,
             refund_notes = $1,
             reconciled_at = COALESCE(reconciled_at, CURRENT_TIMESTAMP),
             reconciled_by = COALESCE(reconciled_by, $2)
           WHERE id = $3 RETURNING *`,
          [refundNotes, req.user!.id, id]
        );

        if (payment.appointment_id) {
          await query(
            `UPDATE appointments SET payment_status = 'refunded'
             WHERE id = $1 AND payment_status = 'paid'`,
            [payment.appointment_id]
          ).catch(() => null);
        }

        return res.json({ ...result.rows[0], refund_channel: refundChannel });
      }

      return res.status(400).json({ message: 'action must be reconcile, unreconcile, or refund' });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/finance/settlements/run', authenticate, async (req: AuthedRequest, res) => {
    if (!['finance', 'admin'].includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const created: any[] = [];
      const doctors = await query(
        `SELECT doctor_user_id, SUM(amount) AS amount
         FROM doctor_earnings WHERE status = 'accrued'
         GROUP BY doctor_user_id`
      );
      for (const row of doctors.rows) {
        const seq = await query(`SELECT nextval('settlement_code_seq') AS n`);
        const user = await query('SELECT name FROM users WHERE id = $1', [row.doctor_user_id]);
        const s = await query(
          `INSERT INTO settlements (settlement_code, payee_type, payee_name, payee_user_id, amount, status, notes)
           VALUES ($1,'doctor',$2,$3,$4,'pending','Clinician consult fees') RETURNING *`,
          [`STL-${String(seq.rows[0].n).padStart(6, '0')}`, user.rows[0]?.name || 'Doctor', row.doctor_user_id, row.amount]
        );
        await query(`UPDATE doctor_earnings SET status = 'settled' WHERE doctor_user_id = $1 AND status = 'accrued'`, [
          row.doctor_user_id,
        ]);
        created.push(s.rows[0]);
      }

      const pharmacies = await query(
        `SELECT o.id, o.name, COUNT(pr.id) AS n
         FROM prescriptions pr JOIN partner_orgs o ON pr.pharmacy_id = o.id
         WHERE pr.dispense_status = 'dispensed'
           AND NOT EXISTS (SELECT 1 FROM settlements s WHERE s.payee_org_id = o.id AND s.notes LIKE 'Pharmacy dispense%')
         GROUP BY o.id, o.name`
      );
      for (const row of pharmacies.rows) {
        const seq = await query(`SELECT nextval('settlement_code_seq') AS n`);
        const s = await query(
          `INSERT INTO settlements (settlement_code, payee_type, payee_name, payee_org_id, amount, status, notes)
           VALUES ($1,'pharmacy',$2,$3,$4,'pending',$5) RETURNING *`,
          [
            `STL-${String(seq.rows[0].n).padStart(6, '0')}`,
            row.name,
            row.id,
            Number(row.n) * 15,
            `Pharmacy dispense x${row.n}`,
          ]
        );
        created.push(s.rows[0]);
      }

      res.json({ created });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/finance/settlements/:id', authenticate, async (req: AuthedRequest, res) => {
    if (!['finance', 'admin'].includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const result = await query(
        `UPDATE settlements SET
           status = COALESCE($1, status),
           paid_at = CASE WHEN $1 = 'paid' THEN CURRENT_TIMESTAMP ELSE paid_at END
         WHERE id = $2 RETURNING *`,
        [req.body.status || null, req.params.id]
      );
      res.json(result.rows[0]);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });
}
