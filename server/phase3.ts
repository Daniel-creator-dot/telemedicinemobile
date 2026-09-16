import type { Express, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import { query } from './db';
import { getPatientForUser } from './phase1';
import { commercialOrgId } from './phase5';
import { getActiveMembership, membershipEligibilityOverlay } from './membership';

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

const CONSULT_FEE = 50;
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

  await seedCommercial();
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
    return {
      source: usedMembership ? 'membership' : 'corporate',
      eligible: true,
      consult_fee: fee,
      copay: best,
      covered_amount: Math.max(0, fee - best),
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
        return res.json({ corporate: null, members: [], billed: { billed: 0, claims: 0 } });
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
      res.json({
        corporate: corp.rows[0] || null,
        corporates: corp.rows,
        members: members.rows,
        billed: spend.rows[0],
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
      const result = await query(
        `UPDATE corporate_members SET status = COALESCE($1, status) WHERE id = $2 RETURNING *`,
        [req.body.status || null, req.params.id]
      );
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
        return res.json({ insurer: null, policies: [], preauths: [], claims: [] });
      }
      const insurer = scopedId
        ? await query('SELECT * FROM insurers WHERE id = $1', [scopedId])
        : await query('SELECT * FROM insurers ORDER BY id');
      const insIds = insurer.rows.map((i: { id: number }) => i.id);
      const [policies, preauths, claims] = await Promise.all([
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
        query(
          `SELECT pa.*, pt.full_name, pt.patient_code
           FROM preauths pa JOIN patients pt ON pa.patient_id = pt.id
           ORDER BY pa.created_at DESC`
        ),
        query(
          `SELECT c.*, pt.full_name, pt.patient_code
           FROM claims c JOIN patients pt ON c.patient_id = pt.id
           ORDER BY c.submitted_at DESC`
        ),
      ]);
      res.json({
        insurer: insurer.rows[0] || null,
        insurers: insurer.rows,
        policies: policies.rows,
        preauths: preauths.rows,
        claims: claims.rows,
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
      res.json(result.rows[0]);
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
      const allowed = ['submitted', 'approved', 'paid', 'rejected'];
      if (status && !allowed.includes(status)) return res.status(400).json({ message: 'Invalid status' });
      const result = await query(
        `UPDATE claims SET
           status = COALESCE($1, status),
           notes = COALESCE($2, notes),
           paid_at = CASE WHEN $1 = 'paid' THEN CURRENT_TIMESTAMP ELSE paid_at END
         WHERE id = $3 RETURNING *`,
        [status || null, notes || null, req.params.id]
      );
      const row = result.rows[0];
      if (row?.patient_id && status === 'paid') {
        const p = await query('SELECT user_id FROM patients WHERE id = $1', [row.patient_id]);
        await notifyUser(deps, p.rows[0]?.user_id, 'Claim paid', `${row.claim_code} of GHS ${row.amount} was settled.`, 'billing');
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
          (SELECT COALESCE(SUM(amount),0) FROM claims WHERE status = 'submitted') AS open_claims
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
      res.json({
        stats: stats.rows[0],
        earnings: earnings.rows,
        settlements: settlements.rows,
        claims: claims.rows,
      });
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
