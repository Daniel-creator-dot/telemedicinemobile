import type { Express, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from './db';
import {
  checkOtpRateLimit,
  recordOtpFailure,
  assertAppointmentAccess,
  getDoctorForUser,
  serializeAppointment,
} from './authz';
import { getAccessiblePatientIds, getPatientForUser } from './patients';
import { createSecureJitsiLink, normalizeJitsiMeetingLink } from './jitsi';
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

const DEFAULT_WORKING_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

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
        ALTER TABLE doctors ADD COLUMN consultation_fee DECIMAL(10,2) DEFAULT 120;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='facility') THEN
        ALTER TABLE doctors ADD COLUMN facility VARCHAR(120);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='is_online') THEN
        ALTER TABLE doctors ADD COLUMN is_online BOOLEAN DEFAULT FALSE;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='doctors' AND column_name='last_seen_at') THEN
        ALTER TABLE doctors ADD COLUMN last_seen_at TIMESTAMPTZ;
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
    CREATE TABLE IF NOT EXISTS chat_thread_reads (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      appointment_id INTEGER NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
      last_read_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (user_id, appointment_id)
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
  await ensureDemoPatient();

  await query(`
    UPDATE doctors SET
      title = COALESCE(title, 'Dr'),
      facility = COALESCE(facility, 'Medilynks Virtual Clinic'),
      languages = COALESCE(languages, 'English, Twi'),
      consultation_fee = COALESCE(consultation_fee, 120),
      years_experience = COALESCE(years_experience, 5),
      qualifications = COALESCE(qualifications, 'MBChB'),
      biography = COALESCE(biography, 'Licensed clinician on the Medilynks network.'),
      working_days = COALESCE(working_days, ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']::text[]),
      start_time = COALESCE(start_time, '09:00'),
      end_time = COALESCE(end_time, '17:00'),
      slot_duration = COALESCE(NULLIF(slot_duration, 0), 30)
    WHERE title IS NULL OR facility IS NULL OR working_days IS NULL
  `);

  console.log('Phase 1 schema ready');
}

async function ensureDemoClinicians() {
  const hashed = await bcrypt.hash('staff123', 10);
  const clinicians = [
    {
      username: 'dr_appiah',
      name: 'Dr. Kwesi Appiah',
      spec: 'General Physician',
      langs: 'English, Twi',
      fee: 120,
      years: 12,
      bio: 'Family physician at Medilynks Virtual Clinic, Accra.',
    },
    {
      username: 'dr_mensah',
      name: 'Dr. Sarah Mensah',
      spec: 'Pediatrician',
      langs: 'English, Ga, Twi',
      fee: 60,
      years: 9,
      bio: 'Paediatrician covering child consults and follow-up on the Medilynks network.',
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
    const found = await query('SELECT id FROM users WHERE username = $1', [d.username]);
    let userId: number;
    if (found.rows[0]) {
      userId = found.rows[0].id;
      await query(
        `UPDATE users SET password = $1, role = 'doctor', name = $2 WHERE id = $3`,
        [hashed, d.name, userId]
      );
    } else {
      const user = await query(
        `INSERT INTO users (username, password, role, name) VALUES ($1, $2, 'doctor', $3) RETURNING id`,
        [d.username, hashed, d.name]
      );
      userId = user.rows[0].id;
    }

    const profile = await query('SELECT id FROM doctors WHERE user_id = $1', [userId]);
    if (!profile.rows[0]) {
      await query(
        `INSERT INTO doctors (
           user_id, name, specialization, slot_duration, start_time, end_time, working_days,
           title, languages, consultation_fee, years_experience, qualifications, biography, facility, is_active, is_online
         ) VALUES ($1, $2, $3, 30, '09:00', '17:00', $8, 'Dr', $4, $5, $6, 'MBChB, MWACP', $7, 'Medilynks Virtual Clinic', TRUE, FALSE)`,
        [userId, d.name, d.spec, d.langs, d.fee, d.years, d.bio, DEFAULT_WORKING_DAYS]
      );
    } else {
      await query(
        `UPDATE doctors SET
           working_days = COALESCE(working_days, $1),
           start_time = COALESCE(start_time, '09:00'),
           end_time = COALESCE(end_time, '17:00'),
           slot_duration = COALESCE(NULLIF(slot_duration, 0), 30),
           consultation_fee = CASE
             WHEN specialization ILIKE '%general%' AND (consultation_fee IS NULL OR consultation_fee = 50) THEN $3
             ELSE COALESCE(consultation_fee, $3)
           END,
           is_active = TRUE
         WHERE user_id = $2`,
        [DEFAULT_WORKING_DAYS, userId, d.fee]
      );
    }
  }
  // Migrate legacy general consult default (GHS 50 → 120)
  await query(
    `UPDATE doctors SET consultation_fee = 120
     WHERE (consultation_fee IS NULL OR consultation_fee = 50)
       AND (specialization ILIKE '%general%' OR specialization IS NULL OR specialization = '')`
  ).catch(() => null);
  console.log('Demo clinicians ready (dr_appiah / dr_mensah / dr_doe, password staff123)');
}

async function ensureDemoPatient() {
  const phone = '0241555000';
  const hashed = await bcrypt.hash('patient123', 10);
  const found = await query(
    `SELECT id FROM users WHERE username = $1 OR phone_number = $1 OR phone_number = $2`,
    [phone, '233241555000']
  );
  let userId: number;
  if (found.rows[0]) {
    userId = found.rows[0].id;
    await query(
      `UPDATE users SET password = $1, role = 'patient', name = COALESCE(NULLIF(name, ''), $2), phone_number = $3, username = $3 WHERE id = $4`,
      [hashed, 'Abena Mensah', phone, userId]
    );
  } else {
    const user = await query(
      `INSERT INTO users (username, password, role, name, phone_number) VALUES ($1, $2, 'patient', $3, $1) RETURNING id`,
      [phone, hashed, 'Abena Mensah']
    );
    userId = user.rows[0].id;
  }

  const patient = await query('SELECT id, patient_code FROM patients WHERE user_id = $1', [userId]);
  if (!patient.rows[0]) {
    const code = await nextPatientCode();
    await query(
      `INSERT INTO patients (user_id, patient_code, full_name, phone_number, email)
       VALUES ($1, $2, 'Abena Mensah', $3, 'abena@example.com')`,
      [userId, code, phone]
    );
    const pid = (await query('SELECT id FROM patients WHERE user_id = $1', [userId])).rows[0]?.id;
    if (pid) {
      for (const type of ['telemedicine', 'privacy', 'comms']) {
        await query(
          'INSERT INTO consents (patient_id, consent_type, accepted) VALUES ($1, $2, TRUE)',
          [pid, type]
        );
      }
    }
  } else if (!patient.rows[0].patient_code) {
    const code = await nextPatientCode();
    await query('UPDATE patients SET patient_code = $1 WHERE user_id = $2', [code, userId]);
  }
  console.log('Demo patient ready (0241555000 / patient123)');
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

function localDateStr(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function addDaysIso(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T12:00:00`);
  d.setDate(d.getDate() + days);
  return localDateStr(d);
}

function doctorWorkingDays(doctor: any): string[] {
  const raw = doctor.working_days;
  if (Array.isArray(raw) && raw.length > 0) return raw.map(String);
  return DEFAULT_WORKING_DAYS;
}

function doctorSchedule(doctor: any): { start: string; end: string; duration: number } {
  // Prefer explicit schedule; otherwise sensible clinic defaults (09:00–17:00 / 30 min).
  const hasStart = doctor.start_time != null && String(doctor.start_time).trim() !== '';
  const hasEnd = doctor.end_time != null && String(doctor.end_time).trim() !== '';
  const hasDuration = doctor.slot_duration != null && Number(doctor.slot_duration) > 0;
  return {
    start: String(hasStart ? doctor.start_time : '09:00:00').slice(0, 5),
    end: String(hasEnd ? doctor.end_time : '17:00:00').slice(0, 5),
    duration: hasDuration ? Number(doctor.slot_duration) : 30,
  };
}

export async function buildSlotsForDoctor(doctor: any, date: string): Promise<string[]> {
  const dayName = new Date(`${date}T12:00:00`).toLocaleDateString('en-US', { weekday: 'long' });
  const working = doctorWorkingDays(doctor);
  if (!working.includes(dayName)) return [];

  const { start, end, duration } = doctorSchedule(doctor);
  const booked = await query(
    `SELECT preferred_time FROM appointments
     WHERE doctor_id = $1 AND preferred_date = $2
       AND status NOT IN ('cancelled', 'missed')`,
    [doctor.id, date]
  );
  const taken = new Set(booked.rows.map((r: any) => String(r.preferred_time).slice(0, 5)));

  const todayStr = localDateStr(new Date());
  const now = new Date();
  const nowMins = now.getHours() * 60 + now.getMinutes();

  const slots: string[] = [];
  let [h, m] = start.split(':').map(Number);
  const [eh, em] = end.split(':').map(Number);
  // Guard against bad schedules that never produce slots.
  const step = Number.isFinite(duration) && duration > 0 ? duration : 30;
  let guard = 0;
  while ((h < eh || (h === eh && m < em)) && guard < 200) {
    guard += 1;
    const label = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
    const slotMins = h * 60 + m;
    const isPastToday = date === todayStr && slotMins <= nowMins;
    if (!taken.has(label) && !isPastToday) slots.push(label);
    m += step;
    while (m >= 60) {
      m -= 60;
      h += 1;
    }
  }
  return slots;
}

async function findNextAvailableDate(doctor: any, fromDate: string, maxDays: number): Promise<string | null> {
  for (let i = 1; i <= maxDays; i++) {
    const candidate = addDaysIso(fromDate, i);
    const slots = await buildSlotsForDoctor(doctor, candidate);
    if (slots.length > 0) return candidate;
  }
  return null;
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
        `Medilynks: your ${usePurpose === 'register' ? 'registration' : 'password reset'} code is ${otp}. It expires in 10 minutes.`
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

      await notifyUser(deps, user.id, 'Welcome to Medilynks', `Your Patient ID is ${patientCode}.`, 'account');

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
      const phone =
        typeof b.phone_number === 'string' && b.phone_number.trim()
          ? b.phone_number.trim()
          : null;

      if (phone) {
        const clash = await query(
          'SELECT id FROM users WHERE (phone_number = $1 OR username = $1) AND id <> $2',
          [phone, req.user!.id]
        );
        if (clash.rows.length) {
          return res.status(409).json({ message: 'Phone number already in use' });
        }
      }

      const result = await query(
        `UPDATE patients SET
          full_name = COALESCE($1, full_name),
          email = COALESCE($2, email),
          phone_number = COALESCE($3, phone_number),
          date_of_birth = COALESCE($4, date_of_birth),
          sex = COALESCE($5, sex),
          region = COALESCE($6, region),
          town = COALESCE($7, town),
          address = COALESCE($8, address),
          occupation = COALESCE($9, occupation),
          emergency_name = COALESCE($10, emergency_name),
          emergency_phone = COALESCE($11, emergency_phone),
          next_of_kin_name = COALESCE($12, next_of_kin_name),
          next_of_kin_phone = COALESCE($13, next_of_kin_phone),
          blood_group = COALESCE($14, blood_group),
          genotype = COALESCE($15, genotype),
          allergies = COALESCE($16, allergies),
          chronic_conditions = COALESCE($17, chronic_conditions),
          current_medications = COALESCE($18, current_medications),
          previous_diagnoses = COALESCE($19, previous_diagnoses),
          surgeries = COALESCE($20, surgeries),
          family_history = COALESCE($21, family_history),
          social_history = COALESCE($22, social_history),
          preferred_location = COALESCE($23, preferred_location),
          nationwide_id = COALESCE($24, nationwide_id),
          profile_complete = TRUE
         WHERE id = $25 RETURNING *`,
        [
          b.full_name, b.email, phone, b.date_of_birth || null, b.sex, b.region, b.town, b.address,
          b.occupation, b.emergency_name, b.emergency_phone, b.next_of_kin_name, b.next_of_kin_phone,
          b.blood_group, b.genotype, b.allergies, b.chronic_conditions, b.current_medications,
          b.previous_diagnoses, b.surgeries, b.family_history, b.social_history, b.preferred_location,
          b.nationwide_id, patient.id,
        ]
      );

      // Keep login + SMS in sync with the patient profile phone/email/name.
      await query(
        `UPDATE users SET
          name = COALESCE($1, name),
          email = COALESCE($2, email),
          phone_number = COALESCE($3, phone_number),
          username = CASE
            WHEN $3::text IS NOT NULL AND (username = phone_number OR username = $4)
            THEN $3
            ELSE username
          END
         WHERE id = $5`,
        [b.full_name || null, b.email || null, phone, patient.phone_number || null, req.user!.id]
      );

      // Keep open-visit SMS targets on the current phone after profile edits.
      if (phone) {
        await query(
          `UPDATE appointments
           SET phone_number = $1
           WHERE patient_id = $2
             AND status NOT IN ('completed', 'cancelled', 'missed')`,
          [phone, patient.id]
        );
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
      const cutoff = Date.now() - 90_000;
      res.json(
        result.rows.map((r: any) => ({
          ...r,
          is_online: Boolean(
            r.is_online && r.last_seen_at && new Date(r.last_seen_at).getTime() > cutoff
          ),
        }))
      );
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/doctors/:id/slots', authenticate, async (req, res) => {
    try {
      const rawId = Number(req.params.id);
      // Accept doctors.id, or fall back to users.id → doctors.user_id (directory vs legacy mismatch).
      let doc = await query('SELECT * FROM doctors WHERE id = $1 AND is_active = TRUE', [rawId]);
      if (!doc.rows[0]) {
        doc = await query('SELECT * FROM doctors WHERE user_id = $1 AND is_active = TRUE', [rawId]);
      }
      if (!doc.rows[0]) return res.status(404).json({ message: 'Doctor not found' });

      const doctor = doc.rows[0];
      const doctorId = doctor.id as number;
      const date = String(req.query.date || localDateStr(new Date()));

      const slots = await buildSlotsForDoctor(doctor, date);
      let nextAvailableDate: string | null = null;
      if (slots.length === 0) {
        nextAvailableDate = await findNextAvailableDate(doctor, date, 14);
      }
      res.json({ date, slots, doctor_id: doctorId, next_available_date: nextAvailableDate });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/doctors/me/availability', authenticate, async (req: AuthedRequest, res) => {
    if (req.user!.role !== 'doctor') return res.status(403).json({ message: 'Forbidden' });
    try {
      const { is_online, working_days, start_time, end_time, slot_duration, consultation_fee } = req.body;
      const online =
        typeof is_online === 'boolean'
          ? is_online
          : is_online === 'true' || is_online === 1 || is_online === '1'
            ? true
            : is_online === 'false' || is_online === 0 || is_online === '0'
              ? false
              : null;

      const result = await query(
        `UPDATE doctors SET
          is_online = CASE WHEN $1::boolean IS NULL THEN is_online ELSE $1::boolean END,
          last_seen_at = CASE
            WHEN $1::boolean IS TRUE THEN CURRENT_TIMESTAMP
            WHEN $1::boolean IS FALSE THEN last_seen_at
            WHEN COALESCE(is_online, FALSE) = TRUE THEN CURRENT_TIMESTAMP
            ELSE last_seen_at
          END,
          working_days = COALESCE($2, working_days),
          start_time = COALESCE($3, start_time),
          end_time = COALESCE($4, end_time),
          slot_duration = COALESCE($5, slot_duration),
          consultation_fee = COALESCE($6, consultation_fee)
         WHERE user_id = $7 RETURNING *`,
        [online, working_days || null, start_time || null, end_time || null, slot_duration || null, consultation_fee || null, req.user!.id]
      );
      if (!result.rows[0]) return res.status(404).json({ message: 'Doctor profile not found' });
      res.json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  /** Heartbeat so presence expires if the doctor app dies while still marked online. */
  app.post('/api/doctors/me/heartbeat', authenticate, async (req: AuthedRequest, res) => {
    if (req.user!.role !== 'doctor') return res.status(403).json({ message: 'Forbidden' });
    try {
      const result = await query(
        `UPDATE doctors
         SET last_seen_at = CURRENT_TIMESTAMP
         WHERE user_id = $1 AND COALESCE(is_online, FALSE) = TRUE
         RETURNING id, is_online, last_seen_at`,
        [req.user!.id]
      );
      res.json(result.rows[0] || { is_online: false });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/doctors/me', authenticate, async (req: AuthedRequest, res) => {
    if (req.user!.role !== 'doctor') return res.status(403).json({ message: 'Forbidden' });
    try {
      const result = await query(
        `SELECT d.*, u.name as user_name, u.phone_number
         FROM doctors d
         LEFT JOIN users u ON d.user_id = u.id
         WHERE d.user_id = $1
         LIMIT 1`,
        [req.user!.id]
      );
      if (!result.rows[0]) return res.status(404).json({ message: 'Doctor profile not found' });
      res.json(result.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  /** Lightweight presence map for patient UIs to poll. Online requires a recent heartbeat. */
  app.get('/api/doctors/presence', authenticate, async (_req, res) => {
    try {
      const result = await query(
        `SELECT id, name,
                (
                  COALESCE(is_online, FALSE) = TRUE
                  AND last_seen_at IS NOT NULL
                  AND last_seen_at > NOW() - INTERVAL '90 seconds'
                ) AS is_online
         FROM doctors
         WHERE is_active = TRUE
         ORDER BY is_online DESC, name ASC`
      );
      res.json(result.rows);
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
        } else {
          const normalized = normalizeJitsiMeetingLink(row.meeting_link);
          if (normalized && normalized !== row.meeting_link) {
            const updated = await query(
              'UPDATE appointments SET meeting_link = $1 WHERE id = $2 RETURNING *',
              [normalized, row.id]
            );
            row = updated.rows[0] ?? { ...row, meeting_link: normalized };
          }
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
        `SELECT id FROM doctors
         WHERE is_active = TRUE
           AND COALESCE(is_online, FALSE) = TRUE
           AND last_seen_at IS NOT NULL
           AND last_seen_at > NOW() - INTERVAL '90 seconds'
         ORDER BY id LIMIT 1`
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
      res.json(
        result.rows.map((row: any) => ({
          ...row,
          preferred_date:
            row.preferred_date instanceof Date
              ? row.preferred_date.toISOString().slice(0, 10)
              : String(row.preferred_date || '').slice(0, 10),
        }))
      );
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/queue/:id/assign', authenticate, async (req: AuthedRequest, res) => {
    const allowed = ['nurse', 'medical_ops', 'admin'];
    if (!allowed.includes(req.user!.role)) return res.status(403).json({ message: 'Forbidden' });
    try {
      const { doctor_id, urgency, status, notes, triage_urgency } = req.body;
      const result = await query(
        `UPDATE appointments SET
          doctor_id = COALESCE($1, doctor_id),
          priority = COALESCE($2, priority),
          status = COALESCE($3, status)
         WHERE id = $4 RETURNING *`,
        [doctor_id || null, urgency || null, status || null, req.params.id]
      );
      if (triage_urgency || notes || req.body.urgency) {
        await query(
          `UPDATE triage_records SET
            urgency = COALESCE($1, urgency),
            notes = COALESCE($2, notes),
            nurse_id = $3,
            status = 'reviewed'
           WHERE appointment_id = $4`,
          [triage_urgency || null, notes || req.body.notes || null, req.user!.id, req.params.id]
        );
      }
      const apt = result.rows[0];
      // Notify assigned doctor and patient
      if (doctor_id) {
        const doc = await query('SELECT user_id, name FROM doctors WHERE id = $1', [doctor_id]);
        const uid = doc.rows[0]?.user_id;
        if (uid) {
          await notifyUser(
            deps,
            uid,
            'Patient assigned to you',
            `A triage patient was handed to ${doc.rows[0]?.name || 'you'} from the live queue.`,
            'queue'
          );
        }
        if (apt?.patient_id) {
          const patient = await query(
            'SELECT user_id, full_name FROM patients WHERE id = $1',
            [apt.patient_id]
          );
          const patientUserId = patient.rows[0]?.user_id;
          if (patientUserId) {
            await notifyUser(
              deps,
              patientUserId,
              'Doctor ready for your visit',
              `${doc.rows[0]?.name || 'Your clinician'} is ready. Open Consult Now to join the video room.`,
              'queue'
            );
          }
        }
      }
      res.json(apt);
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

  async function accessibleChatAppointmentsSql(user: { id: number; role: string }) {
    if (['admin', 'medical_ops', 'nurse'].includes(user.role)) {
      return { where: `a.status <> 'cancelled'`, params: [] as unknown[] };
    }
    if (user.role === 'doctor') {
      const doc = await getDoctorForUser(user.id);
      return {
        where: `a.status <> 'cancelled' AND a.doctor_id = $1`,
        params: [doc?.id ?? -1] as unknown[],
      };
    }
    const ids = await getAccessiblePatientIds(user.id);
    const userRow = await query('SELECT phone_number FROM users WHERE id = $1', [user.id]);
    const phone = String(userRow.rows[0]?.phone_number || '').trim();
    if (phone) {
      return {
        where: `a.status <> 'cancelled' AND (a.patient_id = ANY($1::int[]) OR a.phone_number = $2)`,
        params: [ids, phone] as unknown[],
      };
    }
    return {
      where: `a.status <> 'cancelled' AND a.patient_id = ANY($1::int[])`,
      params: [ids] as unknown[],
    };
  }

  app.get('/api/chat/me/threads', authenticate, async (req: AuthedRequest, res) => {
    try {
      const userId = req.user!.id;
      const access = await accessibleChatAppointmentsSql(req.user!);
      const userParamIndex = access.params.length + 1;
      const result = await query(
        `SELECT
           a.*,
           d.name AS doctor_name,
           lm.body AS last_body,
           lm.sender_name AS last_sender_name,
           lm.created_at AS last_created_at,
           COALESCE((
             SELECT COUNT(*)::int
             FROM chat_messages cm
             WHERE cm.appointment_id = a.id
               AND cm.sender_id IS DISTINCT FROM $${userParamIndex}
               AND cm.created_at > COALESCE(ctr.last_read_at, TIMESTAMP '1970-01-01')
           ), 0) AS unread_count
         FROM appointments a
         LEFT JOIN doctors d ON a.doctor_id = d.id
         LEFT JOIN chat_thread_reads ctr
           ON ctr.appointment_id = a.id AND ctr.user_id = $${userParamIndex}
         LEFT JOIN LATERAL (
           SELECT body, sender_name, created_at
           FROM chat_messages
           WHERE appointment_id = a.id
           ORDER BY created_at DESC
           LIMIT 1
         ) lm ON TRUE
         WHERE ${access.where}
         ORDER BY COALESCE(lm.created_at, a.created_at, a.preferred_date::timestamp) DESC NULLS LAST
         LIMIT 80`,
        [...access.params, userId]
      );
      res.json(
        result.rows.map((row) => {
          const apt = serializeAppointment(row);
          return {
            appointment: apt,
            last_message: row.last_body
              ? `${row.last_sender_name || 'Care team'}: ${row.last_body}`
              : 'Tap to start a clinical message',
            last_created_at: row.last_created_at || null,
            unread_count: Number(row.unread_count) || 0,
          };
        })
      );
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/chat/me/unread-count', authenticate, async (req: AuthedRequest, res) => {
    try {
      const userId = req.user!.id;
      const access = await accessibleChatAppointmentsSql(req.user!);
      const userParamIndex = access.params.length + 1;
      const result = await query(
        `SELECT COALESCE(SUM(thread_unread), 0)::int AS count
         FROM (
           SELECT (
             SELECT COUNT(*)::int
             FROM chat_messages cm
             WHERE cm.appointment_id = a.id
               AND cm.sender_id IS DISTINCT FROM $${userParamIndex}
               AND cm.created_at > COALESCE(ctr.last_read_at, TIMESTAMP '1970-01-01')
           ) AS thread_unread
           FROM appointments a
           LEFT JOIN chat_thread_reads ctr
             ON ctr.appointment_id = a.id AND ctr.user_id = $${userParamIndex}
           WHERE ${access.where}
         ) t`,
        [...access.params, userId]
      );
      res.json({ count: result.rows[0]?.count ?? 0 });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/chat/:appointmentId/read', authenticate, async (req: AuthedRequest, res) => {
    try {
      const apt = await assertAppointmentAccess(req, res, String(req.params.appointmentId));
      if (!apt) return;
      await query(
        `INSERT INTO chat_thread_reads (user_id, appointment_id, last_read_at)
         VALUES ($1, $2, CURRENT_TIMESTAMP)
         ON CONFLICT (user_id, appointment_id)
         DO UPDATE SET last_read_at = EXCLUDED.last_read_at`,
        [req.user!.id, apt.id]
      );
      res.json({ message: 'Chat marked as read' });
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
      // Sender has seen their own thread through the latest message.
      await query(
        `INSERT INTO chat_thread_reads (user_id, appointment_id, last_read_at)
         VALUES ($1, $2, CURRENT_TIMESTAMP)
         ON CONFLICT (user_id, appointment_id)
         DO UPDATE SET last_read_at = EXCLUDED.last_read_at`,
        [req.user!.id, apt.id]
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
         WHERE user_id = $1
         ORDER BY created_at DESC LIMIT 40`,
        [req.user!.id]
      );
      res.json(result.rows);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/notifications/me/unread-count', authenticate, async (req: AuthedRequest, res) => {
    try {
      const result = await query(
        `SELECT COUNT(*)::int AS count FROM notifications
         WHERE user_id = $1 AND is_read = FALSE`,
        [req.user!.id]
      );
      res.json({ count: result.rows[0]?.count ?? 0 });
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
          (SELECT COUNT(*) FROM doctors
            WHERE is_active = TRUE
              AND COALESCE(is_online, FALSE) = TRUE
              AND last_seen_at IS NOT NULL
              AND last_seen_at > NOW() - INTERVAL '90 seconds') AS doctors_online,
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
