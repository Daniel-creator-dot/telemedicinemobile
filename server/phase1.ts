import type { Express, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from './db';
import { checkOtpRateLimit, recordOtpFailure, assertAppointmentAccess } from './authz';
import { getAccessiblePatientIds, getPatientForUser } from './patients';
import { createSecureJitsiLink } from './jitsi';
import { getActiveMembership } from './membership';

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

const CONSULT_TYPES = [
  'general consultation',
  'specialist consultation',
  'follow-up',
  'prescription review',
  'laboratory-result review',
  'imaging-result review',
  'chronic disease review',
  'second medical opinion',
  'other',
];

function notifyDebugOtp() {
  return process.env.NODE_ENV !== 'production';
}

function createJitsiMeetingLink() {
  return createSecureJitsiLink();
}

export async function initPhase1Schema() {
  await query(`CREATE SEQUENCE IF NOT EXISTS patient_code_seq START 100001`);

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='email') THEN
        ALTER TABLE users ADD COLUMN email VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='user_id') THEN
        ALTER TABLE patients ADD COLUMN user_id INTEGER REFERENCES users(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='patient_code') THEN
        ALTER TABLE patients ADD COLUMN patient_code VARCHAR(20) UNIQUE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='date_of_birth') THEN
        ALTER TABLE patients ADD COLUMN date_of_birth DATE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='sex') THEN
        ALTER TABLE patients ADD COLUMN sex VARCHAR(20);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='region') THEN
        ALTER TABLE patients ADD COLUMN region VARCHAR(80);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='town') THEN
        ALTER TABLE patients ADD COLUMN town VARCHAR(80);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='address') THEN
        ALTER TABLE patients ADD COLUMN address TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='occupation') THEN
        ALTER TABLE patients ADD COLUMN occupation VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='emergency_name') THEN
        ALTER TABLE patients ADD COLUMN emergency_name VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='emergency_phone') THEN
        ALTER TABLE patients ADD COLUMN emergency_phone VARCHAR(20);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='next_of_kin_name') THEN
        ALTER TABLE patients ADD COLUMN next_of_kin_name VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='next_of_kin_phone') THEN
        ALTER TABLE patients ADD COLUMN next_of_kin_phone VARCHAR(20);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='blood_group') THEN
        ALTER TABLE patients ADD COLUMN blood_group VARCHAR(10);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='genotype') THEN
        ALTER TABLE patients ADD COLUMN genotype VARCHAR(10);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='allergies') THEN
        ALTER TABLE patients ADD COLUMN allergies TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='chronic_conditions') THEN
        ALTER TABLE patients ADD COLUMN chronic_conditions TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='current_medications') THEN
        ALTER TABLE patients ADD COLUMN current_medications TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='previous_diagnoses') THEN
        ALTER TABLE patients ADD COLUMN previous_diagnoses TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='surgeries') THEN
        ALTER TABLE patients ADD COLUMN surgeries TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='family_history') THEN
        ALTER TABLE patients ADD COLUMN family_history TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='social_history') THEN
        ALTER TABLE patients ADD COLUMN social_history TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='preferred_location') THEN
        ALTER TABLE patients ADD COLUMN preferred_location VARCHAR(100);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='patients' AND column_name='profile_complete') THEN
        ALTER TABLE patients ADD COLUMN profile_complete BOOLEAN DEFAULT FALSE;
      END IF;
    END $$;
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS consents (
      id SERIAL PRIMARY KEY,
      patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      consent_type VARCHAR(50) NOT NULL,
      version VARCHAR(20) DEFAULT '1.0',
      accepted BOOLEAN NOT NULL DEFAULT FALSE,
      accepted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='otps' AND column_name='purpose') THEN
        ALTER TABLE otps ADD COLUMN purpose VARCHAR(20) DEFAULT 'reset';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='otps' AND column_name='phone_number') THEN
        ALTER TABLE otps ADD COLUMN phone_number VARCHAR(20);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='appointments' AND column_name='booking_type') THEN
        ALTER TABLE appointments ADD COLUMN booking_type VARCHAR(30) DEFAULT 'scheduled';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='appointments' AND column_name='consult_type') THEN
        ALTER TABLE appointments ADD COLUMN consult_type VARCHAR(80);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='appointments' AND column_name='eta_minutes') THEN
        ALTER TABLE appointments ADD COLUMN eta_minutes INTEGER;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='title') THEN
        ALTER TABLE doctors ADD COLUMN title VARCHAR(40);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='qualifications') THEN
        ALTER TABLE doctors ADD COLUMN qualifications TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='registration_number') THEN
        ALTER TABLE doctors ADD COLUMN registration_number VARCHAR(80);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='years_experience') THEN
        ALTER TABLE doctors ADD COLUMN years_experience INTEGER;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='languages') THEN
        ALTER TABLE doctors ADD COLUMN languages TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='biography') THEN
        ALTER TABLE doctors ADD COLUMN biography TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='consultation_fee') THEN
        ALTER TABLE doctors ADD COLUMN consultation_fee DECIMAL(10,2) DEFAULT 50;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='facility') THEN
        ALTER TABLE doctors ADD COLUMN facility VARCHAR(120);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='is_online') THEN
        ALTER TABLE doctors ADD COLUMN is_online BOOLEAN DEFAULT FALSE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='prescription_ref') THEN
        ALTER TABLE prescriptions ADD COLUMN prescription_ref VARCHAR(30);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='strength') THEN
        ALTER TABLE prescriptions ADD COLUMN strength VARCHAR(80);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='route') THEN
        ALTER TABLE prescriptions ADD COLUMN route VARCHAR(40);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='prescriptions' AND column_name='quantity') THEN
        ALTER TABLE prescriptions ADD COLUMN quantity VARCHAR(40);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='hpc') THEN
        ALTER TABLE consultations ADD COLUMN hpc TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='medical_history') THEN
        ALTER TABLE consultations ADD COLUMN medical_history TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='working_diagnosis') THEN
        ALTER TABLE consultations ADD COLUMN working_diagnosis TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='differential') THEN
        ALTER TABLE consultations ADD COLUMN differential TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='treatment_plan') THEN
        ALTER TABLE consultations ADD COLUMN treatment_plan TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='patient_education') THEN
        ALTER TABLE consultations ADD COLUMN patient_education TEXT;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='started_at') THEN
        ALTER TABLE consultations ADD COLUMN started_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='consultations' AND column_name='ended_at') THEN
        ALTER TABLE consultations ADD COLUMN ended_at TIMESTAMP;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='notifications' AND column_name='user_id') THEN
        ALTER TABLE notifications ADD COLUMN user_id INTEGER REFERENCES users(id);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='notifications' AND column_name='title') THEN
        ALTER TABLE notifications ADD COLUMN title VARCHAR(160);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='notifications' AND column_name='type') THEN
        ALTER TABLE notifications ADD COLUMN type VARCHAR(50);
      END IF;
    END $$;
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS triage_records (
      id SERIAL PRIMARY KEY,
      appointment_id INTEGER REFERENCES appointments(id) ON DELETE CASCADE,
      patient_id INTEGER REFERENCES patients(id),
      nurse_id INTEGER REFERENCES users(id),
      complaint TEXT,
      duration VARCHAR(80),
      symptoms TEXT,
      medications TEXT,
      allergies TEXT,
      conditions TEXT,
      recent_investigations TEXT,
      vitals_bp VARCHAR(20),
      vitals_temp VARCHAR(10),
      vitals_pulse VARCHAR(10),
      vitals_spo2 VARCHAR(10),
      urgency VARCHAR(20) DEFAULT 'routine',
      notes TEXT,
      status VARCHAR(20) DEFAULT 'submitted',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS chat_messages (
      id SERIAL PRIMARY KEY,
      appointment_id INTEGER REFERENCES appointments(id) ON DELETE CASCADE,
      sender_id INTEGER REFERENCES users(id),
      sender_role VARCHAR(30),
      sender_name VARCHAR(100),
      body TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    UPDATE patients SET patient_code = 'DH-' || LPAD(id::text, 6, '0')
    WHERE patient_code IS NULL
  `);

  const nurseCount = await query("SELECT COUNT(*) FROM users WHERE role = 'nurse'");
  if (parseInt(nurseCount.rows[0].count, 10) === 0) {
    const hashed = await bcrypt.hash('nurse123', 10);
    await query(
      'INSERT INTO users (username, password, role, name, phone_number) VALUES ($1, $2, $3, $4, $5)',
      ['nurse', hashed, 'nurse', 'Triage Nurse', '0240000001']
    );
    console.log('Default nurse user created (nurse/nurse123)');
  }

  const opsCount = await query("SELECT COUNT(*) FROM users WHERE role = 'medical_ops'");
  if (parseInt(opsCount.rows[0].count, 10) === 0) {
    const hashed = await bcrypt.hash('ops123', 10);
    await query(
      'INSERT INTO users (username, password, role, name, phone_number) VALUES ($1, $2, $3, $4, $5)',
      ['medops', hashed, 'medical_ops', 'Medical Operations Lead', '0240000002']
    );
    console.log('Default medical ops user created (medops/ops123)');
  }

  await ensureDemoClinicians();

  await query(`
    UPDATE doctors SET
      title = COALESCE(title, 'Dr'),
      facility = COALESCE(facility, 'Digi Health Virtual Clinic'),
      languages = COALESCE(languages, 'English, Twi'),
      consultation_fee = COALESCE(consultation_fee, 50),
      years_experience = COALESCE(years_experience, 5),
      qualifications = COALESCE(qualifications, 'MBChB'),
      biography = COALESCE(biography, 'Licensed clinician on the Digi Health network.')
    WHERE title IS NULL OR facility IS NULL
  `);

  console.log('Phase 1 schema ready');
}

async function ensureDemoClinicians() {
  const existing = await query("SELECT COUNT(*) FROM users WHERE role = 'doctor'");
  if (parseInt(existing.rows[0].count, 10) > 0) return;

  const hashed = await bcrypt.hash('staff123', 10);
  const clinicians = [
    {
      username: 'dr_appiah',
      name: 'Dr. Kwesi Appiah',
      spec: 'General Physician',
      langs: 'English, Twi',
      fee: 50,
      years: 12,
      bio: 'Family physician at Digi Health Virtual Clinic, Accra.',
    },
    {
      username: 'dr_mensah',
      name: 'Dr. Sarah Mensah',
      spec: 'Pediatrician',
      langs: 'English, Ga, Twi',
      fee: 60,
      years: 9,
      bio: 'Paediatrician covering child consults and follow-up on the Digi Health network.',
    },
    {
      username: 'dr_doe',
      name: 'Dr. John Doe',
      spec: 'Cardiologist',
      langs: 'English, Ewe',
      fee: 80,
      years: 15,
      bio: 'Cardiologist for chest pain, hypertension, and chronic heart follow-up.',
    },
  ];

  for (const d of clinicians) {
    const user = await query(
      `INSERT INTO users (username, password, role, name) VALUES ($1, $2, 'doctor', $3) RETURNING id`,
      [d.username, hashed, d.name]
    );
    await query(
      `INSERT INTO doctors (
         user_id, name, specialization, slot_duration, start_time, end_time,
         title, languages, consultation_fee, years_experience, qualifications, biography, facility, is_active, is_online
       ) VALUES ($1, $2, $3, 20, '08:00', '17:00', 'Dr', $4, $5, $6, 'MBChB, MWACP', $7, 'Digi Health Virtual Clinic', TRUE, TRUE)`,
      [user.rows[0].id, d.name, d.spec, d.langs, d.fee, d.years, d.bio]
    );
  }
  console.log('Demo clinicians created (dr_appiah / dr_mensah / dr_doe, password staff123)');
}

async function nextPatientCode() {
  const r = await query(`SELECT nextval('patient_code_seq') AS n`);
  return `DH-${String(r.rows[0].n).padStart(6, '0')}`;
}

export { getPatientForUser };

async function notifyUser(
  deps: Deps,
  userId: number | null,
  title: string,
  message: string,
  type = 'general'
) {
  await query(
    'INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, $4)',
    [userId, title, message, type]
  );
  if (userId) {
    await deps.sendPushNotification([userId], title, message, { type });
  }
}

function publicUser(user: any, extras: Record<string, unknown> = {}) {
  return {
    id: user.id,
    username: user.username,
    role: user.role,
    name: user.name,
    phone_number: user.phone_number,
    email: user.email,
    ...extras,
  };
}

export function registerPhase1Routes(app: Express, deps: Deps) {
  const { authenticate, sendSMS } = deps;

  app.get('/api/meta/consult-types', (_req, res) => {
    res.json(CONSULT_TYPES);
  });

  app.post('/api/auth/request-otp', async (req, res) => {
    const { phone, purpose } = req.body as { phone?: string; purpose?: string };
    const usePurpose = purpose === 'register' ? 'register' : 'reset';
    if (!phone) return res.status(400).json({ message: 'Phone number is required' });

    try {
      const limited = checkOtpRateLimit(`otp:${phone}:${usePurpose}`, 'request');
      if (!limited.ok) {
        return res.status(429).json({ message: 'Too many OTP requests. Try again later.' });
      }
      if (usePurpose === 'register') {
        const exists = await query(
          'SELECT id FROM users WHERE phone_number = $1 OR username = $1',
          [phone]
        );
        if (exists.rows.length > 0) {
          return res.status(400).json({ message: 'An account already exists for this phone number' });
        }
      } else {
        const user = await query(
          'SELECT * FROM users WHERE phone_number = $1 OR username = $1',
          [phone]
        );
        if (!user.rows[0]) {
          return res.json({ message: 'If an account exists for that number, a code has been sent.' });
        }
      }

      const otp = Math.floor(100000 + Math.random() * 900000).toString();
      const expiresAt = new Date(Date.now() + 10 * 60000);
      await query('DELETE FROM otps WHERE phone_number = $1 AND purpose = $2', [phone, usePurpose]);
      await query(
        'INSERT INTO otps (username, code, expires_at, purpose, phone_number) VALUES ($1, $2, $3, $4, $5)',
        [phone, otp, expiresAt, usePurpose, phone]
      );

      console.log(`[OTP ${usePurpose}] ${phone}: ${otp}`);
      await sendSMS(
        phone,
        `Digi Health: your ${usePurpose === 'register' ? 'registration' : 'password reset'} code is ${otp}. It expires in 10 minutes.`
      );

      res.json({
        message: 'OTP sent to your phone number.',
        ...(notifyDebugOtp() ? { debug_otp: otp } : {}),
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not send OTP' });
    }
  });

  app.post('/api/auth/register-otp', async (req, res) => {
    const {
      phone,
      code,
      password,
      name,
      email,
      consents,
    } = req.body as {
      phone?: string;
      code?: string;
      password?: string;
      name?: string;
      email?: string;
      consents?: { type: string; accepted: boolean }[];
    };

    if (!phone || !code || !password || !name) {
      return res.status(400).json({ message: 'Phone, OTP, name and password are required' });
    }

    try {
      const otpResult = await query(
        `SELECT * FROM otps
         WHERE phone_number = $1 AND code = $2 AND purpose = 'register' AND expires_at > NOW()`,
        [phone, code]
      );
      if (otpResult.rows.length === 0) {
        recordOtpFailure(`otp-verify:${phone}`);
        return res.status(400).json({ message: 'Invalid or expired OTP' });
      }

      const exists = await query(
        'SELECT id FROM users WHERE username = $1 OR phone_number = $1',
        [phone]
      );
      if (exists.rows.length > 0) {
        return res.status(400).json({ message: 'An account already exists for this phone number' });
      }

      const hashed = await bcrypt.hash(password, 10);
      const userResult = await query(
        `INSERT INTO users (username, password, role, name, phone_number, email)
         VALUES ($1, $2, 'patient', $3, $4, $5)
         RETURNING id, username, role, name, phone_number, email`,
        [phone, hashed, name, phone, email || null]
      );
      const user = userResult.rows[0];
      const patientCode = await nextPatientCode();

      const patientResult = await query(
        `INSERT INTO patients (user_id, patient_code, full_name, email, phone_number)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [user.id, patientCode, name, email || null, phone]
      );
      const patient = patientResult.rows[0];

      const accepted = (consents || []).filter((c) => c.accepted);
      for (const c of accepted) {
        await query(
          'INSERT INTO consents (patient_id, consent_type, accepted) VALUES ($1, $2, TRUE)',
          [patient.id, c.type]
        );
      }

      await query('DELETE FROM otps WHERE phone_number = $1 AND purpose = $2', [phone, 'register']);

      const token = jwt.sign(
        { id: user.id, username: user.username, role: user.role },
        process.env.JWT_SECRET!,
        { expiresIn: '24h' }
      );

      await notifyUser(deps, user.id, 'Welcome to Digi Health', `Your Patient ID is ${patientCode}.`, 'account');

      res.status(201).json({
        token,
        user: publicUser(user, { patient_code: patientCode, patient_id: patient.id }),
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Registration failed' });
    }
  });

  app.get('/api/patients/me', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.status(404).json({ message: 'Patient profile not found' });
      const consents = await query(
        'SELECT consent_type, version, accepted, accepted_at FROM consents WHERE patient_id = $1 ORDER BY accepted_at DESC',
        [patient.id]
      );
      res.json({ ...patient, consents: consents.rows });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.put('/api/patients/me', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.status(404).json({ message: 'Patient profile not found' });

      const b = req.body;
      const result = await query(
        `UPDATE patients SET
          full_name = COALESCE($1, full_name),
          email = COALESCE($2, email),
          date_of_birth = COALESCE($3, date_of_birth),
          sex = COALESCE($4, sex),
          region = COALESCE($5, region),
          town = COALESCE($6, town),
          address = COALESCE($7, address),
          occupation = COALESCE($8, occupation),
          emergency_name = COALESCE($9, emergency_name),
          emergency_phone = COALESCE($10, emergency_phone),
          next_of_kin_name = COALESCE($11, next_of_kin_name),
          next_of_kin_phone = COALESCE($12, next_of_kin_phone),
          blood_group = COALESCE($13, blood_group),
          genotype = COALESCE($14, genotype),
          allergies = COALESCE($15, allergies),
          chronic_conditions = COALESCE($16, chronic_conditions),
          current_medications = COALESCE($17, current_medications),
          previous_diagnoses = COALESCE($18, previous_diagnoses),
          surgeries = COALESCE($19, surgeries),
          family_history = COALESCE($20, family_history),
          social_history = COALESCE($21, social_history),
          preferred_location = COALESCE($22, preferred_location),
          nationwide_id = COALESCE($23, nationwide_id),
          profile_complete = TRUE
         WHERE id = $24 RETURNING *`,
        [
          b.full_name, b.email, b.date_of_birth || null, b.sex, b.region, b.town, b.address,
          b.occupation, b.emergency_name, b.emergency_phone, b.next_of_kin_name, b.next_of_kin_phone,
          b.blood_group, b.genotype, b.allergies, b.chronic_conditions, b.current_medications,
          b.previous_diagnoses, b.surgeries, b.family_history, b.social_history, b.preferred_location,
          b.nationwide_id, patient.id,
        ]
      );

      if (b.full_name) {
        await query('UPDATE users SET name = $1, email = COALESCE($2, email) WHERE id = $3', [
          b.full_name, b.email || null, req.user!.id,
        ]);
      }

      res.json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not update profile' });
    }
  });

  app.get('/api/doctors/directory', authenticate, async (req, res) => {
    try {
      const { specialty, q, language, region } = req.query;
      let sql = `
        SELECT d.*, u.name as user_name, u.phone_number
        FROM doctors d
        LEFT JOIN users u ON d.user_id = u.id
        WHERE d.is_active = TRUE
      `;
      const params: unknown[] = [];
      if (specialty) {
        params.push(`%${specialty}%`);
        sql += ` AND d.specialization ILIKE $${params.length}`;
      }
      if (language) {
        params.push(`%${language}%`);
        sql += ` AND COALESCE(d.languages, '') ILIKE $${params.length}`;
      }
      if (region) {
        params.push(`%${region}%`);
        sql += ` AND (COALESCE(d.facility, '') ILIKE $${params.length} OR COALESCE(d.name, '') ILIKE $${params.length})`;
      }
      if (q) {
        params.push(`%${q}%`);
        sql += ` AND (d.name ILIKE $${params.length} OR d.specialization ILIKE $${params.length} OR COALESCE(d.languages,'') ILIKE $${params.length} OR COALESCE(d.facility,'') ILIKE $${params.length})`;
      }
      sql += ' ORDER BY d.is_online DESC, d.name ASC';
      const result = await query(sql, params);
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/doctors/:id/slots', authenticate, async (req, res) => {
    try {
      const doctorId = Number(req.params.id);
      const date = String(req.query.date || new Date().toISOString().slice(0, 10));
      const doc = await query('SELECT * FROM doctors WHERE id = $1 AND is_active = TRUE', [doctorId]);
      if (!doc.rows[0]) return res.status(404).json({ message: 'Doctor not found' });

      const doctor = doc.rows[0];
      const dayName = new Date(`${date}T12:00:00`).toLocaleDateString('en-US', { weekday: 'long' });
      const working: string[] = doctor.working_days || ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
      if (working.length && !working.includes(dayName)) {
        return res.json({ date, slots: [] });
      }

      const start = String(doctor.start_time || '08:00:00').slice(0, 5);
      const end = String(doctor.end_time || '17:00:00').slice(0, 5);
      const duration = Number(doctor.slot_duration || 15);
      const booked = await query(
        `SELECT preferred_time FROM appointments
         WHERE doctor_id = $1 AND preferred_date = $2
           AND status NOT IN ('cancelled', 'missed')`,
        [doctorId, date]
      );
      const taken = new Set(
        booked.rows.map((r: any) => String(r.preferred_time).slice(0, 5))
      );

      const slots: string[] = [];
      let [h, m] = start.split(':').map(Number);
      const [eh, em] = end.split(':').map(Number);
      while (h < eh || (h === eh && m < em)) {
        const label = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
        if (!taken.has(label)) slots.push(label);
        m += duration;
        while (m >= 60) {
          m -= 60;
          h += 1;
        }
      }
      res.json({ date, slots });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/doctors/me/availability', authenticate, async (req: AuthedRequest, res) => {
    if (req.user!.role !== 'doctor') return res.status(403).json({ message: 'Forbidden' });
    try {
      const { is_online, working_days, start_time, end_time, slot_duration, consultation_fee } = req.body;
      const result = await query(
        `UPDATE doctors SET
          is_online = COALESCE($1, is_online),
          working_days = COALESCE($2, working_days),
          start_time = COALESCE($3, start_time),
          end_time = COALESCE($4, end_time),
          slot_duration = COALESCE($5, slot_duration),
          consultation_fee = COALESCE($6, consultation_fee)
         WHERE user_id = $7 RETURNING *`,
        [is_online, working_days || null, start_time || null, end_time || null, slot_duration || null, consultation_fee || null, req.user!.id]
      );
      if (!result.rows[0]) return res.status(404).json({ message: 'Doctor profile not found' });
      res.json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/queue/consult-now', authenticate, async (req: AuthedRequest, res) => {
    if (req.user!.role !== 'patient') return res.status(403).json({ message: 'Patients only' });
    try {
      const guardian = await getPatientForUser(req.user!.id);
      if (!guardian) return res.status(400).json({ message: 'Complete registration first' });
      if (guardian.is_restricted) {
        return res.status(403).json({ message: 'Booking restricted due to repeated no-shows.' });
      }

      const {
        consult_type,
        reason,
        complaint,
        duration,
        symptoms,
        medications,
        allergies,
        conditions,
        recent_investigations,
        vitals_bp,
        vitals_temp,
        vitals_pulse,
        vitals_spo2,
        dependent_patient_id,
      } = req.body;

      let patient = guardian;
      if (dependent_patient_id) {
        const ids = await getAccessiblePatientIds(req.user!.id);
        if (!ids.includes(Number(dependent_patient_id))) {
          return res.status(403).json({ message: 'Forbidden' });
        }
        const dep = await query('SELECT * FROM patients WHERE id = $1', [dependent_patient_id]);
        if (!dep.rows[0]) return res.status(404).json({ message: 'Dependent not found' });
        patient = dep.rows[0];
      }

      const existing = await query(
        `SELECT * FROM appointments
         WHERE patient_id = $1 AND booking_type = 'consult_now'
           AND status IN ('queued', 'pending', 'approved', 'arrived', 'consulting')
         ORDER BY created_at DESC LIMIT 1`,
        [patient.id]
      );
      if (existing.rows[0]) {
        let row = existing.rows[0];
        if (!row.meeting_link) {
          const meetingLink = createJitsiMeetingLink();
          const updated = await query(
            'UPDATE appointments SET meeting_link = $1 WHERE id = $2 RETURNING *',
            [meetingLink, row.id]
          );
          row = updated.rows[0] ?? row;
        }
        return res.json({ already_in_queue: true, appointment: row });
      }

      const qn = await query(
        `SELECT COALESCE(MAX(queue_number), 0) + 1 AS n
         FROM appointments WHERE preferred_date = CURRENT_DATE AND booking_type = 'consult_now'`
      );
      const queueNumber = qn.rows[0].n;
      const membership = await getActiveMembership(guardian.id);
      const priority = membership?.plan?.queuePriority || 'High';
      const eta = membership?.plan?.etaMinutes ?? queueNumber * 12;

      const online = await query(
        `SELECT id FROM doctors WHERE is_active = TRUE AND is_online = TRUE ORDER BY id LIMIT 1`
      );
      const fallback = await query(`SELECT id FROM doctors WHERE is_active = TRUE ORDER BY id LIMIT 1`);
      const doctorId = online.rows[0]?.id || fallback.rows[0]?.id || null;

      const now = new Date();
      const time = now.toTimeString().slice(0, 8);
      const date = now.toISOString().slice(0, 10);
      const appointmentId = 'NOW-' + Math.random().toString(36).substring(2, 8).toUpperCase();

      const meetingLink = createJitsiMeetingLink();
      const apt = await query(
        `INSERT INTO appointments (
          appointment_id, patient_id, full_name, phone_number, email, doctor_id,
          preferred_date, preferred_time, status, priority, notes, service,
          is_telemedicine, booking_type, consult_type, queue_number, eta_minutes, meeting_link
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'queued',$9,$10,$11, TRUE, 'consult_now', $12, $13, $14, $15)
        RETURNING *`,
        [
          appointmentId,
          patient.id,
          patient.full_name,
          guardian.phone_number,
          guardian.email || patient.email,
          doctorId,
          date,
          time,
          priority,
          reason || complaint || 'Consult Now',
          consult_type || 'general consultation',
          consult_type || 'general consultation',
          queueNumber,
          eta,
          meetingLink,
        ]
      );

      await query(
        `INSERT INTO triage_records (
          appointment_id, patient_id, complaint, duration, symptoms, medications,
          allergies, conditions, recent_investigations, vitals_bp, vitals_temp, vitals_pulse, vitals_spo2, urgency
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'urgent')`,
        [
          apt.rows[0].id, patient.id, complaint || reason, duration, symptoms, medications,
          allergies || patient.allergies, conditions || patient.chronic_conditions,
          recent_investigations, vitals_bp, vitals_temp, vitals_pulse, vitals_spo2,
        ]
      );

      const staff = await query("SELECT id FROM users WHERE role IN ('nurse', 'medical_ops', 'admin')");
      await notifyUser(
        deps,
        req.user!.id,
        'You joined the live queue',
        `Queue number ${queueNumber}. Estimated wait ${eta} minutes.`,
        'queue'
      );
      for (const s of staff.rows) {
        await notifyUser(deps, s.id, 'Consult Now', `${patient.full_name} joined the live queue (#${queueNumber}).`, 'queue');
      }

      res.status(201).json(apt.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not join queue' });
    }
  });

  app.get('/api/queue', authenticate, async (req: AuthedRequest, res) => {
    try {
      const role = req.user!.role;
      let sql = `
        SELECT a.*, d.name as doctor_name, t.urgency, t.complaint, t.status as triage_status, t.id as triage_id
        FROM appointments a
        LEFT JOIN doctors d ON a.doctor_id = d.id
        LEFT JOIN triage_records t ON t.appointment_id = a.id
        WHERE a.booking_type = 'consult_now'
          AND a.status IN ('queued', 'pending', 'approved', 'arrived', 'consulting')
      `;
      const params: unknown[] = [];
      if (role === 'doctor') {
        const doc = await query('SELECT id FROM doctors WHERE user_id = $1', [req.user!.id]);
        if (!doc.rows[0]) return res.json([]);
        params.push(doc.rows[0].id);
        sql += ` AND a.doctor_id = $${params.length}`;
      } else if (role === 'patient') {
        const patient = await getPatientForUser(req.user!.id);
        if (!patient) return res.json([]);
        params.push(patient.id);
        sql += ` AND a.patient_id = $${params.length}`;
      }
      sql += ' ORDER BY a.queue_number ASC NULLS LAST, a.created_at ASC';
      const result = await query(sql, params);
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/queue/:id/assign', authenticate, async (req: AuthedRequest, res) => {
    const allowed = ['nurse', 'medical_ops', 'admin'];
    if (!allowed.includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const { doctor_id, urgency, status } = req.body;
      const result = await query(
        `UPDATE appointments SET
          doctor_id = COALESCE($1, doctor_id),
          priority = COALESCE($2, priority),
          status = COALESCE($3, status)
         WHERE id = $4 RETURNING *`,
        [doctor_id || null, urgency || null, status || null, req.params.id]
      );
      if (req.body.urgency || req.body.notes) {
        await query(
          `UPDATE triage_records SET
            urgency = COALESCE($1, urgency),
            notes = COALESCE($2, notes),
            nurse_id = $3,
            status = 'reviewed'
           WHERE appointment_id = $4`,
          [req.body.urgency || null, req.body.notes || null, req.user!.id, req.params.id]
        );
      }
      res.json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/triage', authenticate, async (req: AuthedRequest, res) => {
    const allowed = ['nurse', 'medical_ops', 'admin', 'doctor'];
    if (!allowed.includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const result = await query(`
        SELECT t.*, a.appointment_id as apt_code, a.id as appointment_pk, a.full_name, a.status as appointment_status, a.queue_number, d.name as doctor_name
        FROM triage_records t
        JOIN appointments a ON t.appointment_id = a.id
        LEFT JOIN doctors d ON a.doctor_id = d.id
        WHERE a.status IN ('queued', 'pending', 'approved', 'arrived', 'consulting')
        ORDER BY
          CASE t.urgency WHEN 'emergency' THEN 0 WHEN 'urgent' THEN 1 ELSE 2 END,
          t.created_at ASC
      `);
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.put('/api/triage/:id', authenticate, async (req: AuthedRequest, res) => {
    const allowed = ['nurse', 'medical_ops', 'admin'];
    if (!allowed.includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const b = req.body;
      const result = await query(
        `UPDATE triage_records SET
          complaint = COALESCE($1, complaint),
          duration = COALESCE($2, duration),
          symptoms = COALESCE($3, symptoms),
          medications = COALESCE($4, medications),
          allergies = COALESCE($5, allergies),
          conditions = COALESCE($6, conditions),
          vitals_bp = COALESCE($7, vitals_bp),
          vitals_temp = COALESCE($8, vitals_temp),
          vitals_pulse = COALESCE($9, vitals_pulse),
          vitals_spo2 = COALESCE($10, vitals_spo2),
          urgency = COALESCE($11, urgency),
          notes = COALESCE($12, notes),
          nurse_id = $13,
          status = COALESCE($14, 'reviewed')
         WHERE id = $15 RETURNING *`,
        [
          b.complaint, b.duration, b.symptoms, b.medications, b.allergies, b.conditions,
          b.vitals_bp, b.vitals_temp, b.vitals_pulse, b.vitals_spo2, b.urgency, b.notes,
          req.user!.id, b.status, req.params.id,
        ]
      );
      res.json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/chat/:appointmentId', authenticate, async (req: AuthedRequest, res) => {
    try {
      const apt = await assertAppointmentAccess(req, res, String(req.params.appointmentId));
      if (!apt) return;
      const result = await query(
        `SELECT * FROM chat_messages WHERE appointment_id = $1 ORDER BY created_at ASC`,
        [req.params.appointmentId]
      );
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/chat/:appointmentId', authenticate, async (req: AuthedRequest, res) => {
    const body = String(req.body?.body || '').trim();
    if (!body) return res.status(400).json({ message: 'Message is required' });
    try {
      const apt = await assertAppointmentAccess(req, res, String(req.params.appointmentId));
      if (!apt) return;
      const user = await query('SELECT name, role FROM users WHERE id = $1', [req.user!.id]);
      const result = await query(
        `INSERT INTO chat_messages (appointment_id, sender_id, sender_role, sender_name, body)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [req.params.appointmentId, req.user!.id, req.user!.role, user.rows[0]?.name || req.user!.username, body]
      );
      res.status(201).json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not send message' });
    }
  });

  app.get('/api/notifications/me', authenticate, async (req: AuthedRequest, res) => {
    try {
      const result = await query(
        `SELECT * FROM notifications
         WHERE user_id = $1 OR user_id IS NULL
         ORDER BY created_at DESC LIMIT 40`,
        [req.user!.id]
      );
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/notifications/me/read', authenticate, async (req: AuthedRequest, res) => {
    try {
      await query('UPDATE notifications SET is_read = TRUE WHERE user_id = $1', [req.user!.id]);
      res.json({ message: 'Notifications marked as read' });
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/ops/dashboard', authenticate, async (req: AuthedRequest, res) => {
    const allowed = ['medical_ops', 'admin', 'nurse'];
    if (!allowed.includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const live = await query(`
        SELECT
          (SELECT COUNT(*) FROM doctors WHERE is_active = TRUE AND COALESCE(is_online, FALSE) = TRUE) AS doctors_online,
          (SELECT COUNT(*) FROM doctors WHERE is_active = TRUE) AS doctors_active,
          (SELECT COUNT(*) FROM appointments WHERE status = 'consulting') AS consulting_now,
          (SELECT COUNT(*) FROM appointments WHERE COALESCE(booking_type,'scheduled') = 'consult_now' AND status IN ('queued','pending','approved')) AS patients_waiting,
          (SELECT COALESCE(AVG(eta_minutes), 0) FROM appointments WHERE COALESCE(booking_type,'scheduled') = 'consult_now' AND status IN ('queued','pending')) AS avg_wait,
          (SELECT COUNT(*) FROM appointments WHERE preferred_date = CURRENT_DATE AND status = 'completed') AS completed_today,
          (SELECT COUNT(*) FROM appointments WHERE preferred_date = CURRENT_DATE AND status = 'cancelled') AS cancelled_today,
          (SELECT COUNT(*) FROM appointments WHERE preferred_date = CURRENT_DATE AND status = 'missed') AS missed_today,
          (SELECT COUNT(*) FROM consultations WHERE status != 'completed') AS pending_notes,
          (SELECT COUNT(*) FROM lab_requests WHERE status NOT IN ('completed','cancelled')) AS pending_labs,
          (SELECT COUNT(*) FROM scan_requests WHERE status NOT IN ('completed','cancelled')) AS pending_scans,
          (SELECT COUNT(*) FROM consultations WHERE follow_up_date IS NOT NULL AND follow_up_date < CURRENT_DATE AND status = 'completed') AS overdue_followups,
          (SELECT COUNT(*) FROM prescriptions WHERE COALESCE(dispense_status,'unsent') IN ('sent','received','preparing','ready')) AS pending_pharmacy,
          (SELECT COUNT(*) FROM referrals WHERE status NOT IN ('completed','declined')) AS open_referrals
      `);
      res.json(live.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });
}
