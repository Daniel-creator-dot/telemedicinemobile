import type { Express, Response } from 'express';
import { query } from './db';
import {
  authenticate,
  AuthedRequest,
  assertAppointmentAccess,
  canAccessPatient,
  CLINICAL_STAFF,
  requireRoles,
} from './authz';
import { getAccessiblePatientIds, getPatientForUser } from './patients';
import { getActiveMembership } from './membership';

const AI_DISCLAIMER =
  'Assistive draft only. Not a diagnosis, not medical advice, and not a substitute for a licensed clinician. Medilynks does not claim HIPAA certification.';

const PROGRAM_CATALOG: {
  key: string;
  name: string;
  summary: string;
  tasks: { title: string; cadence: string; daysFromStart: number }[];
}[] = [
  {
    key: 'hypertension',
    name: 'Hypertension',
    summary: 'Home blood-pressure checks, medication reminders, and a clinician review.',
    tasks: [
      { title: 'Take morning blood pressure', cadence: 'daily', daysFromStart: 0 },
      { title: 'Take evening blood pressure', cadence: 'daily', daysFromStart: 0 },
      { title: 'Confirm antihypertensive taken', cadence: 'daily', daysFromStart: 0 },
      { title: 'Clinician review', cadence: 'once', daysFromStart: 28 },
    ],
  },
  {
    key: 'diabetes',
    name: 'Type 2 diabetes',
    summary: 'Glucose logging, medication adherence, and a scheduled review.',
    tasks: [
      { title: 'Log fasting glucose', cadence: 'daily', daysFromStart: 0 },
      { title: 'Confirm diabetes medication taken', cadence: 'daily', daysFromStart: 0 },
      { title: 'Foot check', cadence: 'weekly', daysFromStart: 7 },
      { title: 'Clinician review', cadence: 'once', daysFromStart: 28 },
    ],
  },
  {
    key: 'asthma',
    name: 'Asthma',
    summary: 'Inhaler adherence, symptom diary, and trigger review.',
    tasks: [
      { title: 'Confirm preventer inhaler taken', cadence: 'daily', daysFromStart: 0 },
      { title: 'Log daytime symptoms', cadence: 'daily', daysFromStart: 0 },
      { title: 'Clinician review', cadence: 'once', daysFromStart: 28 },
    ],
  },
  {
    key: 'sickle_cell',
    name: 'Sickle cell',
    summary: 'Hydration, pain diary, and early review if crisis signs appear.',
    tasks: [
      { title: 'Log pain score (0–10)', cadence: 'daily', daysFromStart: 0 },
      { title: 'Confirm daily fluids', cadence: 'daily', daysFromStart: 0 },
      { title: 'Clinician review', cadence: 'once', daysFromStart: 21 },
    ],
  },
  {
    key: 'antenatal',
    name: 'Antenatal care',
    summary: 'Visit reminders and simple well-being checks during pregnancy.',
    tasks: [
      { title: 'Log weight', cadence: 'weekly', daysFromStart: 0 },
      { title: 'Note fetal movement / well-being', cadence: 'daily', daysFromStart: 0 },
      { title: 'Antenatal review visit', cadence: 'once', daysFromStart: 28 },
    ],
  },
];

export async function initPhase4Schema() {
  await query(`
    CREATE TABLE IF NOT EXISTS vault_documents (
      id SERIAL PRIMARY KEY,
      patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      title VARCHAR(160) NOT NULL,
      kind VARCHAR(40) NOT NULL,
      notes TEXT,
      source_label VARCHAR(160),
      created_by INTEGER REFERENCES users(id),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='vault_documents' AND column_name='file_name') THEN
        ALTER TABLE vault_documents ADD COLUMN file_name VARCHAR(200);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='vault_documents' AND column_name='mime_type') THEN
        ALTER TABLE vault_documents ADD COLUMN mime_type VARCHAR(80);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='vault_documents' AND column_name='byte_size') THEN
        ALTER TABLE vault_documents ADD COLUMN byte_size INTEGER;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='vault_documents' AND column_name='content') THEN
        ALTER TABLE vault_documents ADD COLUMN content BYTEA;
      END IF;
    END $$;
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS chronic_program_tasks (
      id SERIAL PRIMARY KEY,
      program_id INTEGER REFERENCES chronic_programs(id) ON DELETE CASCADE,
      title VARCHAR(160) NOT NULL,
      cadence VARCHAR(30) DEFAULT 'once',
      due_on DATE,
      status VARCHAR(20) DEFAULT 'pending',
      notes TEXT,
      completed_at TIMESTAMP
    );
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS chronic_adherence (
      id SERIAL PRIMARY KEY,
      program_id INTEGER REFERENCES chronic_programs(id) ON DELETE CASCADE,
      task_id INTEGER REFERENCES chronic_program_tasks(id) ON DELETE SET NULL,
      value VARCHAR(80),
      notes TEXT,
      recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);

  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='chronic_programs' AND column_name='program_key') THEN
        ALTER TABLE chronic_programs ADD COLUMN program_key VARCHAR(40);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='chronic_programs' AND column_name='enrolled_by') THEN
        ALTER TABLE chronic_programs ADD COLUMN enrolled_by INTEGER REFERENCES users(id);
      END IF;
    END $$;
  `);
}

async function notifyUser(userId: number | null, title: string, message: string, type = 'care') {
  await query(
    'INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, $4)',
    [userId, title, message, type]
  );
}

async function resolveManagedPatient(req: AuthedRequest, requestedId?: number | null) {
  const mine = await getPatientForUser(req.user!.id);
  if (req.user!.role !== 'patient') {
    if (!requestedId) return { error: 'patient_id is required', status: 400 as const, patient: null };
    if (!(await canAccessPatient(req.user!, requestedId))) {
      return { error: 'Forbidden', status: 403 as const, patient: null };
    }
    const row = await query('SELECT * FROM patients WHERE id = $1', [requestedId]);
    if (!row.rows[0]) return { error: 'Patient not found', status: 404 as const, patient: null };
    return { error: null, status: 200 as const, patient: row.rows[0] };
  }
  if (!mine) return { error: 'Complete your medical profile first.', status: 400 as const, patient: null };
  if (!requestedId || Number(requestedId) === Number(mine.id)) {
    return { error: null, status: 200 as const, patient: mine };
  }
  const ids = await getAccessiblePatientIds(req.user!.id);
  if (!ids.includes(Number(requestedId))) {
    return { error: 'Forbidden', status: 403 as const, patient: null };
  }
  const row = await query('SELECT * FROM patients WHERE id = $1', [requestedId]);
  if (!row.rows[0]) return { error: 'Patient not found', status: 404 as const, patient: null };
  return { error: null, status: 200 as const, patient: row.rows[0] };
}

function addDays(days: number) {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

function ruleBasedSoap(input: {
  name?: string;
  complaint?: string;
  symptoms?: string;
  notes?: string;
  vitals?: Record<string, string | undefined>;
  history?: string;
}) {
  const vitalsBits = Object.entries(input.vitals || {})
    .filter(([, v]) => v && String(v).trim())
    .map(([k, v]) => `${k}: ${v}`)
    .join('; ');
  const subjective = [input.complaint, input.symptoms, input.history].filter(Boolean).join('. ');
  const objective = vitalsBits || 'No vitals recorded in this visit yet.';
  return {
    subjective: subjective || `Patient ${input.name || ''} presents for review.`.trim(),
    objective,
    assessment:
      'Working impression to be confirmed by the attending clinician. Template assembled from visit notes and vitals only.',
    plan: [
      input.notes ? `Review clinician notes: ${input.notes}` : 'Complete examination and document findings.',
      'Discuss differential and confirm or revise the working impression.',
      'Agree investigations, treatment, safety-netting, and follow-up with the patient.',
    ].join(' '),
  };
}

function ruleBasedSymptomHelper(complaint: string, symptoms: string) {
  const text = `${complaint} ${symptoms}`.toLowerCase();
  const flags: string[] = [];
  if (/(chest pain|shortness of breath|stroke|unconscious|severe bleeding|suicide|convulsion)/.test(text)) {
    flags.push('Seek emergency care now if this is happening — do not wait for a teleconsult.');
  }
  if (/(fever|temperature)/.test(text)) flags.push('Note temperature, duration, and any recent travel or contacts.');
  if (/(cough|breath)/.test(text)) flags.push('Note whether breathing is comfortable at rest and if there is wheeze or blood.');
  if (/(headache|dizzy)/.test(text)) flags.push('Note sudden onset, vision change, neck stiffness, or weakness.');
  if (flags.length === 0) {
    flags.push('Describe onset, duration, severity, what makes it better or worse, and current medicines.');
  }
  return {
    questions: flags,
    next_step: 'Book or join a Medilynks consult so a clinician can assess you. This helper cannot diagnose.',
  };
}

async function tryOpenAi(system: string, user: string): Promise<string | null> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) return null;
  try {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
        temperature: 0.2,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
    return data.choices?.[0]?.message?.content || null;
  } catch {
    return null;
  }
}

export function registerPhase4Routes(app: Express) {
  app.get('/api/family', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const guardian = await getPatientForUser(req.user!.id);
      if (!guardian) return res.json([]);
      const result = await query(
        `SELECT d.id, d.relationship, d.created_at,
                p.id as patient_id, p.full_name, p.date_of_birth, p.sex, p.phone_number, p.patient_code
         FROM dependents d
         JOIN patients p ON p.id = d.dependent_patient_id
         WHERE d.guardian_patient_id = $1
         ORDER BY d.created_at DESC`,
        [guardian.id]
      );
      res.json(result.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/family', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const guardian = await getPatientForUser(req.user!.id);
      if (!guardian) return res.status(400).json({ message: 'Complete your medical profile first.' });
      const { full_name, date_of_birth, sex, relationship, phone_number } = req.body || {};
      if (!full_name || !relationship) {
        return res.status(400).json({ message: 'Name and relationship are required' });
      }
      const membership = await getActiveMembership(guardian.id);
      const allowed = membership?.plan?.dependents ?? 1;
      const count = await query(
        'SELECT COUNT(*)::int AS n FROM dependents WHERE guardian_patient_id = $1',
        [guardian.id]
      );
      if (Number(count.rows[0]?.n || 0) >= allowed) {
        return res.status(400).json({
          message: `${membership?.plan?.name || 'Classic'} includes ${allowed} dependent${allowed === 1 ? '' : 's'}. Upgrade membership to add more of the household.`,
        });
      }
      const codeRow = await query(`SELECT nextval('patient_code_seq') AS n`);
      const patientCode = `DH-${String(codeRow.rows[0].n).padStart(6, '0')}`;
      const created = await query(
        `INSERT INTO patients (full_name, date_of_birth, sex, phone_number, patient_code)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [
          String(full_name).trim(),
          date_of_birth || null,
          sex || null,
          phone_number || guardian.phone_number,
          patientCode,
        ]
      );
      const dep = created.rows[0];
      const link = await query(
        `INSERT INTO dependents (guardian_patient_id, dependent_patient_id, relationship)
         VALUES ($1, $2, $3)
         ON CONFLICT (guardian_patient_id, dependent_patient_id) DO UPDATE SET relationship = EXCLUDED.relationship
         RETURNING *`,
        [guardian.id, dep.id, String(relationship).trim()]
      );
      res.status(201).json({
        id: link.rows[0].id,
        relationship: link.rows[0].relationship,
        patient_id: dep.id,
        full_name: dep.full_name,
        date_of_birth: dep.date_of_birth,
        sex: dep.sex,
        phone_number: dep.phone_number,
        patient_code: dep.patient_code,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not add dependent' });
    }
  });

  app.delete('/api/family/:id', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const guardian = await getPatientForUser(req.user!.id);
      if (!guardian) return res.status(400).json({ message: 'Complete your medical profile first.' });
      const existing = await query(
        'SELECT * FROM dependents WHERE id = $1 AND guardian_patient_id = $2',
        [req.params.id, guardian.id]
      );
      if (!existing.rows[0]) return res.status(404).json({ message: 'Not found' });
      await query('DELETE FROM dependents WHERE id = $1', [req.params.id]);
      res.json({ message: 'Dependent unlinked' });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/chronic/catalog', authenticate, async (_req, res) => {
    res.json(PROGRAM_CATALOG.map(({ key, name, summary }) => ({ key, name, summary })));
  });

  app.get('/api/chronic/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const ids = req.user!.role === 'patient'
        ? await getAccessiblePatientIds(req.user!.id)
        : [];
      let patientId = req.query.patient_id ? Number(req.query.patient_id) : null;
      if (req.user!.role === 'patient') {
        patientId = patientId && ids.includes(patientId) ? patientId : ids[0] || null;
      } else if (patientId && !(await canAccessPatient(req.user!, patientId))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      if (!patientId) return res.json([]);
      const programs = await query(
        `SELECT * FROM chronic_programs WHERE patient_id = $1 ORDER BY created_at DESC`,
        [patientId]
      );
      const enriched = [];
      for (const program of programs.rows) {
        const tasks = await query(
          `SELECT * FROM chronic_program_tasks WHERE program_id = $1 ORDER BY id`,
          [program.id]
        );
        const done = tasks.rows.filter((t: { status: string }) => t.status === 'done').length;
        enriched.push({
          ...program,
          tasks: tasks.rows,
          adherence: {
            total: tasks.rows.length,
            done,
            percent: tasks.rows.length ? Math.round((done / tasks.rows.length) * 100) : 0,
          },
        });
      }
      res.json(enriched);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/chronic', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const { program_key, condition, next_review, notes, patient_id } = req.body || {};
      const catalog = PROGRAM_CATALOG.find((p) => p.key === program_key);
      const resolved = await resolveManagedPatient(req, patient_id ? Number(patient_id) : null);
      if (resolved.error || !resolved.patient) {
        return res.status(resolved.status).json({ message: resolved.error });
      }
      const name = catalog?.name || condition;
      if (!name) return res.status(400).json({ message: 'Program or condition is required' });

      const existing = await query(
        `SELECT * FROM chronic_programs
         WHERE patient_id = $1 AND status = 'active'
           AND (program_key = $2 OR condition = $3)
         LIMIT 1`,
        [resolved.patient.id, program_key || null, name]
      );
      if (existing.rows[0]) return res.status(200).json(existing.rows[0]);

      const inserted = await query(
        `INSERT INTO chronic_programs (patient_id, condition, status, next_review, notes, program_key, enrolled_by)
         VALUES ($1, $2, 'active', $3, $4, $5, $6) RETURNING *`,
        [
          resolved.patient.id,
          name,
          next_review || addDays(28),
          notes || catalog?.summary || null,
          program_key || null,
          req.user!.id,
        ]
      );
      const program = inserted.rows[0];
      const tasks = catalog?.tasks || [
        { title: 'Daily check-in', cadence: 'daily', daysFromStart: 0 },
        { title: 'Clinician review', cadence: 'once', daysFromStart: 28 },
      ];
      for (const task of tasks) {
        await query(
          `INSERT INTO chronic_program_tasks (program_id, title, cadence, due_on, status)
           VALUES ($1, $2, $3, $4, 'pending')`,
          [program.id, task.title, task.cadence, addDays(task.daysFromStart)]
        );
      }
      const ownerUserId = resolved.patient.user_id || req.user!.id;
      await notifyUser(
        ownerUserId,
        'Care program enrolled',
        `${name} tasks are now on your list. This is a reminder, not a diagnosis.`,
        'chronic'
      );
      const withTasks = await query(`SELECT * FROM chronic_program_tasks WHERE program_id = $1`, [program.id]);
      res.status(201).json({ ...program, tasks: withTasks.rows });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not enroll in program' });
    }
  });

  app.patch('/api/chronic/:id/tasks/:taskId', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const task = await query(
        `SELECT t.*, p.patient_id, p.id as program_id
         FROM chronic_program_tasks t
         JOIN chronic_programs p ON p.id = t.program_id
         WHERE t.id = $1 AND p.id = $2`,
        [req.params.taskId, req.params.id]
      );
      const row = task.rows[0];
      if (!row) return res.status(404).json({ message: 'Not found' });
      if (!(await canAccessPatient(req.user!, row.patient_id))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      const status = req.body?.status === 'pending' ? 'pending' : 'done';
      const updated = await query(
        `UPDATE chronic_program_tasks
         SET status = $1, notes = COALESCE($2, notes),
             completed_at = CASE WHEN $1 = 'done' THEN CURRENT_TIMESTAMP ELSE NULL END
         WHERE id = $3 RETURNING *`,
        [status, req.body?.notes || null, row.id]
      );
      if (status === 'done') {
        await query(
          `INSERT INTO chronic_adherence (program_id, task_id, value, notes) VALUES ($1, $2, $3, $4)`,
          [row.program_id, row.id, req.body?.value || 'done', req.body?.notes || null]
        );
      }
      res.json(updated.rows[0]);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/vault/documents', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const { title, kind, notes, source_label, patient_id, file_base64, file_name, mime_type } = req.body || {};
      if (!title) return res.status(400).json({ message: 'Title is required' });
      const resolved = await resolveManagedPatient(req, patient_id ? Number(patient_id) : null);
      if (resolved.error || !resolved.patient) {
        return res.status(resolved.status).json({ message: resolved.error });
      }
      const allowed = ['letter', 'lab', 'imaging', 'prescription', 'other'];
      const useKind = allowed.includes(kind) ? kind : 'other';

      let content: Buffer | null = null;
      let fileName: string | null = file_name ? String(file_name).slice(0, 200) : null;
      let mime: string | null = mime_type ? String(mime_type).slice(0, 80) : null;
      let byteSize: number | null = null;
      if (file_base64) {
        const raw = String(file_base64).replace(/^data:[^;]+;base64,/, '');
        content = Buffer.from(raw, 'base64');
        if (!content.length) return res.status(400).json({ message: 'File could not be read' });
        if (content.length > 2 * 1024 * 1024) {
          return res.status(413).json({ message: 'File must be 2 MB or smaller' });
        }
        byteSize = content.length;
        if (!fileName) fileName = 'record.bin';
        if (!mime) mime = 'application/octet-stream';
      }

      const result = await query(
        `INSERT INTO vault_documents (patient_id, title, kind, notes, source_label, created_by, file_name, mime_type, byte_size, content)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING id, patient_id, title, kind, notes, source_label, created_by, created_at, file_name, mime_type, byte_size,
                   (content IS NOT NULL) AS has_file`,
        [
          resolved.patient.id,
          String(title).trim(),
          useKind,
          notes || null,
          source_label || null,
          req.user!.id,
          fileName,
          mime,
          byteSize,
          content,
        ]
      );
      res.status(201).json({
        ...result.rows[0],
        storage: content ? 'postgres' : 'metadata',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not add vault record' });
    }
  });

  app.get('/api/vault/documents/:id/file', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const row = await query(
        'SELECT patient_id, file_name, mime_type, content FROM vault_documents WHERE id = $1',
        [req.params.id]
      );
      if (!row.rows[0]) return res.status(404).json({ message: 'Not found' });
      if (!(await canAccessPatient(req.user!, row.rows[0].patient_id))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      if (!row.rows[0].content) return res.status(404).json({ message: 'No file attached' });
      res.setHeader('Content-Type', row.rows[0].mime_type || 'application/octet-stream');
      res.setHeader(
        'Content-Disposition',
        `inline; filename="${String(row.rows[0].file_name || 'record').replace(/"/g, '')}"`
      );
      res.send(row.rows[0].content);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Could not open file' });
    }
  });

  app.delete('/api/vault/documents/:id', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const row = await query('SELECT * FROM vault_documents WHERE id = $1', [req.params.id]);
      if (!row.rows[0]) return res.status(404).json({ message: 'Not found' });
      if (!(await canAccessPatient(req.user!, row.rows[0].patient_id))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      await query('DELETE FROM vault_documents WHERE id = $1', [req.params.id]);
      res.json({ message: 'Removed' });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/ai/assist', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const mode = req.body?.mode === 'symptoms' ? 'symptoms' : 'soap';
      if (mode === 'soap' && !CLINICAL_STAFF.includes(req.user!.role) && req.user!.role !== 'doctor') {
        return res.status(403).json({ message: 'SOAP assist is for clinicians' });
      }
      if (mode === 'symptoms' && req.user!.role !== 'patient' && !CLINICAL_STAFF.includes(req.user!.role)) {
        return res.status(403).json({ message: 'Forbidden' });
      }

      let complaint = String(req.body?.complaint || '');
      let symptoms = String(req.body?.symptoms || '');
      let notes = String(req.body?.notes || '');
      let history = String(req.body?.history || '');
      let name = '';
      const vitals: Record<string, string | undefined> = {
        BP: req.body?.vitals_bp,
        Temp: req.body?.vitals_temp,
        Pulse: req.body?.vitals_pulse,
        SpO2: req.body?.vitals_spo2,
        Weight: req.body?.vitals_weight,
      };

      if (req.body?.appointment_id) {
        const apt = await assertAppointmentAccess(req, res, req.body.appointment_id);
        if (!apt) return;
        name = apt.full_name;
        const consult = await query(
          `SELECT * FROM consultations WHERE appointment_id = $1 ORDER BY id DESC LIMIT 1`,
          [apt.id]
        );
        const c = consult.rows[0];
        if (c) {
          complaint = complaint || c.chief_complaint || '';
          symptoms = symptoms || c.symptoms || '';
          notes = notes || c.clinical_notes || '';
          history = history || c.medical_history || '';
          vitals.BP = vitals.BP || c.vitals_bp;
          vitals.Temp = vitals.Temp || c.vitals_temp;
          vitals.Pulse = vitals.Pulse || c.vitals_pulse;
          vitals.SpO2 = vitals.SpO2 || c.vitals_spo2;
          vitals.Weight = vitals.Weight || c.vitals_weight;
        }
        if (!complaint) complaint = apt.notes || apt.consult_type || '';
      }

      if (mode === 'symptoms') {
        const templated = ruleBasedSymptomHelper(complaint, symptoms);
        const llm = await tryOpenAi(
          'You help patients prepare for a clinician visit. Never diagnose. Never claim HIPAA. Ask clarifying questions and urge emergency care for red flags. Return short JSON with questions[] and next_step.',
          `Complaint: ${complaint}\nSymptoms: ${symptoms}`
        );
        return res.json({
          mode,
          source: llm ? 'llm' : 'template',
          disclaimer: AI_DISCLAIMER,
          ...templated,
          llm_text: llm,
        });
      }

      const soap = ruleBasedSoap({ name, complaint, symptoms, notes, vitals, history });
      const llm = await tryOpenAi(
        'You draft SOAP notes for a licensed clinician. Label output as an assistive draft. Never claim a definitive diagnosis. Never claim HIPAA. Return JSON with subjective, objective, assessment, plan.',
        JSON.stringify({ name, complaint, symptoms, notes, vitals, history })
      );
      res.json({
        mode,
        source: llm ? 'llm' : 'template',
        disclaimer: AI_DISCLAIMER,
        soap,
        llm_text: llm,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Assistive draft unavailable' });
    }
  });

  app.get('/api/admin/ops-summary', authenticate, requireRoles('admin', 'medical_ops'), async (_req, res) => {
    try {
      const [users, apts, programs, docs] = await Promise.all([
        query(`SELECT role, COUNT(*)::int AS n FROM users GROUP BY role`),
        query(
          `SELECT status, COUNT(*)::int AS n FROM appointments
           WHERE preferred_date >= CURRENT_DATE - INTERVAL '7 days' GROUP BY status`
        ),
        query(`SELECT COUNT(*)::int AS n FROM chronic_programs WHERE status = 'active'`),
        query(`SELECT COUNT(*)::int AS n FROM vault_documents`),
      ]);
      res.json({
        users: users.rows,
        appointments_7d: apts.rows,
        active_programs: programs.rows[0]?.n || 0,
        vault_documents: docs.rows[0]?.n || 0,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });
}
