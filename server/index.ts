import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { initDb, query } from './db';
import { registerPhase1Routes, getPatientForUser } from './phase1';
import { registerPhase2Routes, assignNearestPartner, notifyDiagnosticClosedLoop } from './phase2';
import { registerPhase3Routes, recordVisitPayment, getEligibility } from './phase3';
import {
  getPaystackPublicKey,
  getPaystackSecretKey,
  initializePaystackCheckout,
  paystackPaymentEmail,
  verifyPaystackTransaction,
} from './paystack';
import { registerClinicalRoutes } from './clinical';
import { registerPhase4Routes } from './phase4';
import { registerPhase5Routes, registerAuditMiddleware } from './phase5';
import { registerCompleteRoutes } from './complete';
import { registerMembershipRoutes } from './membership';
import { registerPhaseOverviewRoutes } from './phases';
import { createSecureJitsiLink, normalizeJitsiMeetingLink } from './jitsi';
import {
  authenticate,
  requireRoles,
  canAccessPatient,
  getDoctorForUser,
  resolveDoctorId,
  serializeAppointment,
  assertAppointmentAccess,
  publicSettings,
  checkOtpRateLimit,
  recordOtpFailure,
  clearOtpFailures,
  ADMIN_OPS,
  CLINICAL_STAFF,
} from './authz';
import { getAccessiblePatientIds, resolvePatientIdFromAppointment } from './patients';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import axios from 'axios';
import { initializeApp, cert } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

dotenv.config();

// Initialize Firebase Admin
let firebaseApp: any = null;
try {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
    firebaseApp = initializeApp({
      credential: cert(serviceAccount)
    });
    console.log('[FIREBASE] Admin SDK Initialized successfully');
  } else {
    console.warn('[FIREBASE] FIREBASE_SERVICE_ACCOUNT_KEY missing from environment. Push notifications will be simulated.');
  }
} catch (e) {
  console.error('[FIREBASE] Initialization error:', e);
}

// Push notification sender helper
async function sendPushNotification(userIds: number[], title: string, body: string, data?: Record<string, string>) {
  if (!firebaseApp) {
    console.log(`[PUSH SIMULATED] To users ${userIds.join(', ')}: "${title}" - "${body}"`);
    return;
  }

  try {
    // Get FCM tokens for targeted users
    const tokensResult = await query(
      'SELECT token FROM fcm_tokens WHERE user_id = ANY($1)',
      [userIds]
    );
    const tokens = tokensResult.rows.map(r => r.token);

    if (tokens.length === 0) {
      console.log(`[PUSH] No registered FCM tokens for user IDs: ${userIds.join(', ')}`);
      return;
    }

    console.log(`[PUSH] Sending message to ${tokens.length} devices...`);
    const messaging = getMessaging(firebaseApp);
    
    // Send to tokens
    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: data || {},
    });

    console.log(`[PUSH] Successfully sent ${response.successCount} messages; ${response.failureCount} failed.`);
  } catch (err) {
    console.error('[PUSH ERROR] Failed to send push notification:', err);
  }
}

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json({ limit: '4mb' }));
registerAuditMiddleware(app);

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'digihealth' });
});
app.get('/', (_req, res) => {
  res.json({ ok: true, service: 'digihealth' });
});

// Auth middleware lives in ./authz (no token / JWT payload logging).



// --- Auth Routes ---
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;
  try {
    const result = await query(
      'SELECT * FROM users WHERE LOWER(username) = LOWER($1) OR phone_number = $1',
      [String(username || '').trim()]
    );
    const user = result.rows[0];

    if (user && await bcrypt.compare(password, user.password)) {
      const token = jwt.sign(
        { id: user.id, username: user.username, role: user.role },
        process.env.JWT_SECRET!,
        { expiresIn: '24h' }
      );
      let extras: Record<string, unknown> = {};
      if (user.role === 'patient') {
        const patient = await getPatientForUser(user.id);
        if (patient) extras = { patient_code: patient.patient_code, patient_id: patient.id };
      }
      res.json({
        token,
        user: {
          id: user.id,
          username: user.username,
          role: user.role,
          name: user.name,
          phone_number: user.phone_number,
          email: user.email,
          ...extras,
        },
      });
    } else {
      res.status(401).json({ message: 'Invalid credentials' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/auth/register', async (_req, res) => {
  res.status(410).json({
    message: 'Direct registration is closed. Request an OTP, then complete /api/auth/register-otp.',
  });
});



app.post('/api/auth/forgot-password', async (req, res) => {
  const { username } = req.body;
  const generic = { message: 'If an account exists for that identifier, a reset code has been sent.' };
  try {
    const limit = checkOtpRateLimit(`reset:${username}`, 'request');
    if (!limit.ok) {
      return res.status(429).json({ message: 'Too many reset attempts. Try again later.' });
    }

    const userResult = await query('SELECT * FROM users WHERE username = $1 OR phone_number = $1', [username]);
    const user = userResult.rows[0];

    if (user?.phone_number) {
      const otp = Math.floor(100000 + Math.random() * 900000).toString();
      const expiresAt = new Date(Date.now() + 10 * 60000);
      await query('DELETE FROM otps WHERE username = $1', [username]);
      await query('INSERT INTO otps (username, code, expires_at, purpose, phone_number) VALUES ($1, $2, $3, $4, $5)', [
        username, otp, expiresAt, 'reset', user.phone_number,
      ]);
      await sendSMS(
        user.phone_number,
        `Medilynks: your password reset code is ${otp}. It expires in 10 minutes.`
      );
    }

    res.json(generic);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/auth/reset-password', async (req, res) => {
  const { username, code, newPassword } = req.body;
  try {
    const limit = checkOtpRateLimit(`reset-verify:${username}`, 'verify');
    if (!limit.ok) {
      return res.status(429).json({ message: 'Too many attempts. Try again later.' });
    }
    const otpResult = await query(
      `SELECT * FROM otps WHERE (username = $1 OR phone_number = $1) AND code = $2 AND expires_at > NOW()`,
      [username, code]
    );
    
    if (otpResult.rows.length === 0) {
      recordOtpFailure(`reset-verify:${username}`);
      return res.status(400).json({ message: 'Invalid or expired OTP.' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await query('UPDATE users SET password = $1 WHERE username = $2 OR phone_number = $2', [hashedPassword, username]);
    await query('DELETE FROM otps WHERE username = $1 OR phone_number = $1', [username]);
    clearOtpFailures(`reset-verify:${username}`);

    res.json({ message: 'Password reset successful.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Settings Routes ---
app.get('/api/settings', authenticate, async (req: any, res) => {
  try {
    const result = await query('SELECT * FROM settings');
    res.json(publicSettings(result.rows, req.user.role));
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/settings', authenticate, requireRoles('admin'), async (req, res) => {
  const updates = req.body || {};
  try {
    for (const [key, value] of Object.entries(updates)) {
      if ((key === 'sms_api_key' || key === 'paystack_secret_key') && (value === '********' || value === '')) continue;
      await query(
        'INSERT INTO settings (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = $2',
        [key, value]
      );
    }
    res.json({ message: 'Settings updated successfully' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/config/paystack', async (_req, res) => {
  try {
    const publicKey = await getPaystackPublicKey();
    res.json({ publicKey, configured: Boolean(await getPaystackSecretKey()) });
  } catch {
    res.status(500).json({ error: 'Failed to fetch config' });
  }
});

function paystackReturnHtml() {
  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Medilynks</title>
<style>body{font-family:system-ui,sans-serif;background:#F6F3EE;color:#1F4A3A;display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}
.card{background:#fff;padding:28px 24px;border-radius:16px;max-width:360px;text-align:center;box-shadow:0 8px 30px rgba(31,74,58,.08)}
h1{font-size:20px;margin:0 0 8px}p{margin:0;color:#5C6B66;line-height:1.45}</style></head>
<body><div class="card"><h1>Payment received</h1><p>Return to the Medilynks app to confirm your visit. You can close this page.</p></div></body></html>`;
}

app.get('/api/paystack/callback', (_req, res) => {
  res.type('html').send(paystackReturnHtml());
});
app.get('/paystack/callback', (_req, res) => {
  res.type('html').send(paystackReturnHtml());
});

// --- SMS Utility ---
async function sendSMS(recipient: string, message: string) {
  try {
    const settingsResult = await query('SELECT * FROM settings');
    const settings = settingsResult.rows.reduce((acc: any, row: any) => {
      acc[row.key] = row.value;
      return acc;
    }, {});

    const { sms_base_url, sms_sender_id, sms_api_key } = settings;

    if (!sms_base_url) {
      console.warn('SMS Base URL not configured. Skipping SMS.');
      return;
    }

    // Format phone number to international standard (e.g., 050 -> 23350)
    let formattedRecipient = recipient.replace(/[^0-9+]/g, '');
    if (formattedRecipient.startsWith('0')) {
      formattedRecipient = '233' + formattedRecipient.substring(1);
    } else if (formattedRecipient.startsWith('+')) {
      formattedRecipient = formattedRecipient.substring(1);
    }

    console.log(`[SMS SEND] Attempting to send to ${formattedRecipient} via ${sms_base_url}`);

    await axios.post(sms_base_url, {
      sender: sms_sender_id,
      recipients: [formattedRecipient],
      message: message
    }, {
      headers: {
        'Authorization': `Bearer ${sms_api_key}`
      }
    }).then(res => {
      console.log('[SMS SUCCESS]', res.data);
    }).catch(err => {
      console.error('[SMS ERROR]', err.response?.data || err.message);
    });

    await query('INSERT INTO sms_logs (recipient, message, status) VALUES ($1, $2, $3)', [
      recipient, message, 'sent'
    ]);
  } catch (err) {
    console.error('Error in sendSMS utility:', err);
  }
}

// --- User Management Routes ---
app.get('/api/users', authenticate, requireRoles('admin', 'medical_ops'), async (_req, res) => {
  try {
    const result = await query('SELECT id, username, role, name, phone_number FROM users ORDER BY name');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/users', authenticate, requireRoles('admin'), async (req, res) => {
  const { username, password, role, name, phone_number } = req.body;
  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const userResult = await query(
      'INSERT INTO users (username, password, role, name, phone_number) VALUES ($1, $2, $3, $4, $5) RETURNING id, username, role, name, phone_number',
      [username, hashedPassword, role, name, phone_number]
    );
    const newUser = userResult.rows[0];

    // If role is doctor, create doctor profile automatically
    if (role === 'doctor') {
      await query(
        'INSERT INTO doctors (user_id, name, specialization) VALUES ($1, $2, $3)',
        [newUser.id, name, 'General Physician']
      );
    }

    res.status(201).json(newUser);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.put('/api/users/:id', authenticate, requireRoles('admin'), async (req, res) => {
  const { id } = req.params;
  const { username, role, name, phone_number, password } = req.body;
  try {
    let result;
    if (password) {
      const hashedPassword = await bcrypt.hash(password, 10);
      result = await query(
        'UPDATE users SET username = $1, role = $2, name = $3, phone_number = $4, password = $5 WHERE id = $6 RETURNING id, username, role, name, phone_number',
        [username, role, name, phone_number, hashedPassword, id]
      );
    } else {
      result = await query(
        'UPDATE users SET username = $1, role = $2, name = $3, phone_number = $4 WHERE id = $5 RETURNING id, username, role, name, phone_number',
        [username, role, name, phone_number, id]
      );
    }
    
    // If role changed to doctor and they don't have a profile, create one
    if (role === 'doctor' && result.rows[0]) {
      const docCheck = await query('SELECT * FROM doctors WHERE user_id = $1', [id]);
      if (docCheck.rows.length === 0) {
        await query(
          'INSERT INTO doctors (user_id, name, specialization) VALUES ($1, $2, $3)',
          [id, name, 'General Physician']
        );
      }
    }

    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.delete('/api/users/:id', authenticate, requireRoles('admin'), async (req, res) => {
  try {
    await query('DELETE FROM users WHERE id = $1', [req.params.id]);
    res.json({ message: 'User deleted' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Appointment Routes ---
app.get('/api/appointments', authenticate, async (req: any, res) => {
  try {
    let queryText = `
      SELECT a.*, d.name as doctor_name 
      FROM appointments a 
      LEFT JOIN doctors d ON a.doctor_id = d.id 
    `;
    let queryParams: any[] = [];

    if (req.user.role === 'doctor') {
      const doc = await getDoctorForUser(req.user.id);
      if (doc) {
        queryText += ' WHERE a.doctor_id = $1';
        queryParams.push(doc.id);
      } else {
        return res.json([]);
      }
    } else if (req.user.role === 'patient') {
      const ids = await getAccessiblePatientIds(req.user.id);
      const userResult = await query('SELECT phone_number FROM users WHERE id = $1', [req.user.id]);
      queryText += ' WHERE (a.patient_id = ANY($1::int[])) OR a.phone_number = $2';
      queryParams.push(ids, userResult.rows[0]?.phone_number || '');
    } else if (!['admin', 'medical_ops', 'nurse'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }

    queryText += ' ORDER BY a.preferred_date DESC, a.preferred_time DESC';
    
    const result = await query(queryText, queryParams);
    res.json(result.rows.map(serializeAppointment));
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/appointments/my', authenticate, async (req: any, res) => {
  try {
    const ids = await getAccessiblePatientIds(req.user.id);
    const userResult = await query('SELECT phone_number FROM users WHERE id = $1', [req.user.id]);
    const phone = userResult.rows[0]?.phone_number;

    const result = await query(`
      SELECT a.*, d.name as doctor_name 
      FROM appointments a 
      LEFT JOIN doctors d ON a.doctor_id = d.id 
      WHERE (a.patient_id = ANY($1::int[])) OR a.phone_number = $2
      ORDER BY a.preferred_date DESC, a.preferred_time DESC
    `, [ids, phone || '']);
    res.json(result.rows.map(serializeAppointment));
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/appointments/:id', authenticate, async (req: any, res) => {
  const { id } = req.params;
  if (!/^\d+$/.test(String(id))) {
    return res.status(404).json({ message: 'Not found' });
  }
  try {
    const apt = await assertAppointmentAccess(req, res, id);
    if (!apt) return;
    res.json(serializeAppointment(apt));
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/appointments', authenticate, async (req: any, res) => {
    const { 
    fullName, whoIsComing, phoneNumber, email, staffId, nationwideId, department, 
    reason, preferredDate, preferredTime, priority, notes, doctor_id, doctorId, service, isTelemedicine,
    consult_type, booking_type, dependent_patient_id
  } = req.body;
  
  const effectiveStaffId = staffId || null;
  
  try {
    if (req.user.role === 'patient') {
      const mine = await getPatientForUser(req.user.id);
      if (!mine) return res.status(400).json({ message: 'Complete your medical profile first.' });
    } else if (!CLINICAL_STAFF.includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }

    // 1. Check if patient exists (by staffId if available, else by phoneNumber)
    let patientResult;
    if (req.user.role === 'patient') {
      const mine = await getPatientForUser(req.user.id);
      if (dependent_patient_id) {
        const ids = await getAccessiblePatientIds(req.user.id);
        if (!ids.includes(Number(dependent_patient_id))) {
          return res.status(403).json({ message: 'Forbidden' });
        }
        patientResult = await query('SELECT * FROM patients WHERE id = $1', [dependent_patient_id]);
      } else {
        patientResult = { rows: mine ? [mine] : [] };
      }
    } else if (effectiveStaffId) {
      patientResult = await query('SELECT * FROM patients WHERE staff_id = $1', [effectiveStaffId]);
    } else {
      patientResult = await query('SELECT * FROM patients WHERE phone_number = $1', [phoneNumber]);
    }
    let patient = patientResult.rows[0];

    if (patient && patient.is_restricted) {
      return res.status(403).json({ message: 'Booking restricted due to repeated no-shows.' });
    }

    // 2. Register patient if not exists
    if (!patient) {
      const newPatient = await query(`
        INSERT INTO patients (staff_id, nationwide_id, full_name, email, phone_number, department)
        VALUES ($1, $2, $3, $4, $5, $6) RETURNING *
      `, [effectiveStaffId, nationwideId, fullName, email, phoneNumber, department]);
      patient = newPatient.rows[0];
    }

    // Always store doctors.id (never users.id) so doctor list filters match.
    const resolvedDoctorId = await resolveDoctorId(doctor_id ?? doctorId);
    if ((doctor_id ?? doctorId) != null && (doctor_id ?? doctorId) !== '' && resolvedDoctorId == null) {
      return res.status(400).json({ message: 'Unknown doctor. Pick a clinician from the directory.' });
    }

    const appointmentId = 'APT-' + Math.random().toString(36).substring(2, 9).toUpperCase();
    const visitName = dependent_patient_id ? patient.full_name : fullName;

    const result = await query(`
      INSERT INTO appointments (
        appointment_id, patient_id, full_name, who_is_coming, phone_number, email, staff_id, nationwide_id,
        department, notes, preferred_date, preferred_time, priority, doctor_id, service, is_telemedicine,
        consult_type, booking_type, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, 'pending')
      RETURNING *
    `, [
      appointmentId, patient.id, visitName, whoIsComing, phoneNumber, email, staffId, nationwideId,
      department, reason + (notes ? ' | ' + notes : ''), preferredDate, preferredTime, priority || 'Medium', resolvedDoctorId, service, !!isTelemedicine,
      consult_type || service || 'general consultation', booking_type || 'scheduled'
    ]);

    // Never block the booking response on SMS latency.
    sendSMS(
      phoneNumber,
      `Medilynks: appointment ${appointmentId} is booked for ${preferredDate} at ${preferredTime}. Open the app to manage your visit.`
    ).catch((e) => console.error('Patient SMS Error:', e));
    sendSMS(
      '+233200024081',
      `Admin Alert: New appointment ${appointmentId} booked by ${fullName} for ${preferredDate} at ${preferredTime}.`
    ).catch((e) => console.error('Admin SMS Error:', e));

    console.log(`Admin Alert: New appointment ${appointmentId} booked by ${fullName}.`);

    // Notify assigned doctor (users.id via doctors.user_id) + admins
    try {
      const notifyIds: number[] = [];
      if (resolvedDoctorId) {
        const docUser = await query('SELECT user_id, name FROM doctors WHERE id = $1', [resolvedDoctorId]);
        const doctorUserId = docUser.rows[0]?.user_id;
        if (doctorUserId) {
          notifyIds.push(Number(doctorUserId));
          await query(
            `INSERT INTO notifications (user_id, title, message, type) VALUES ($1, $2, $3, $4)`,
            [
              doctorUserId,
              'New appointment booked',
              `${visitName} booked for ${preferredDate} at ${preferredTime}.`,
              'appointment',
            ]
          ).catch(() =>
            query('INSERT INTO notifications (message) VALUES ($1)', [
              `New appointment ${appointmentId} for Dr. ${docUser.rows[0]?.name || resolvedDoctorId}`,
            ])
          );
        }
      }
      const adminUsers = await query("SELECT id FROM users WHERE role = 'admin'");
      for (const r of adminUsers.rows) notifyIds.push(Number(r.id));
      const uniqueIds = [...new Set(notifyIds)];
      if (uniqueIds.length > 0) {
        sendPushNotification(
          uniqueIds,
          'New Appointment Booked',
          `New appointment ${appointmentId} booked by ${fullName} for ${preferredDate} at ${preferredTime}.`,
          { type: 'new-appointment', appointmentId: appointmentId, doctorId: String(resolvedDoctorId || '') }
        ).catch((e) => console.error('Booking push error:', e));
      }
    } catch (notifyErr) {
      console.error('Booking notify error:', notifyErr);
    }

    await query('INSERT INTO notifications (message) VALUES ($1)', [
      `New appointment booked: ${appointmentId} by ${fullName}`
    ]);

    const created = serializeAppointment(result.rows[0]);
    res.status(201).json(created);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/appointments/:id', authenticate, async (req: any, res) => {
  const { id } = req.params;
  const { preferred_date, preferred_time, notes, doctor_id, priority, status, who_is_coming, service, is_telemedicine } = req.body;
  try {
    const existing = await assertAppointmentAccess(req, res, id);
    if (!existing) return;
    if (req.user.role === 'patient' && status && !['cancelled'].includes(status)) {
      return res.status(403).json({ message: 'Patients can only cancel their own visits.' });
    }
    const finalDoctorId = doctor_id === '' ? null : doctor_id;

    const result = await query(
      `UPDATE appointments 
       SET preferred_date = COALESCE($1, preferred_date),
           preferred_time = COALESCE($2, preferred_time),
           notes = COALESCE($3, notes),
           doctor_id = $4,
           priority = COALESCE($5, priority),
           status = COALESCE($6::varchar, status),
           who_is_coming = COALESCE($7, who_is_coming),
           service = COALESCE($8, service),
           is_telemedicine = COALESCE($9, is_telemedicine),
           completed_at = CASE WHEN $6::varchar = 'completed' THEN CURRENT_TIMESTAMP ELSE completed_at END
       WHERE id = $10 RETURNING *`,
      [preferred_date, preferred_time, notes, finalDoctorId, priority, status, who_is_coming, service, is_telemedicine, id]
    );
    const apt = result.rows[0];
    // Trigger SMS Alerts
    if (apt) {
      if (status === 'approved') {
        const docResult = await query('SELECT name FROM doctors WHERE id = $1', [apt.doctor_id]);
        const doctorName = docResult.rows[0]?.name || 'a Physician';
        const dateStr = apt.preferred_date ? new Date(apt.preferred_date).toLocaleDateString() : 'the scheduled date';
        const msg = `Medilynks: appointment ${apt.appointment_id} is confirmed with ${doctorName} for ${dateStr}. Open the app to join or view details.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Edit/Approve:', e));
      } else if (status === 'completed') {
        const docResult = await query('SELECT name FROM doctors WHERE id = $1', [apt.doctor_id]);
        const doctorName = docResult.rows[0]?.name || 'our team';
        const msg = `Medilynks: your visit ${apt.appointment_id} with ${doctorName} is complete. Review notes and prescriptions in the app.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Edit/Complete:', e));
      } else if (status === 'cancelled') {
        const msg = `Medilynks: appointment ${apt.appointment_id} has been cancelled. Open the app to rebook.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Edit/Cancel:', e));
      }

      // Send push notification to the patient
      if (status === 'approved' || status === 'completed' || status === 'cancelled') {
        try {
          const userRes = await query('SELECT id FROM users WHERE phone_number = $1 OR username = $2', [apt.phone_number, apt.email]);
          const userIds = userRes.rows.map(r => r.id);
          if (userIds.length > 0) {
            let title = 'Appointment Update';
            let body = `Your appointment ${apt.appointment_id} status has been updated to ${status}.`;
            if (status === 'approved') {
              title = 'Appointment Approved';
              body = `Your appointment ${apt.appointment_id} has been approved.`;
            } else if (status === 'completed') {
              title = 'Appointment Completed';
              body = `Your appointment ${apt.appointment_id} has been marked as completed. Thank you!`;
            } else if (status === 'cancelled') {
              title = 'Appointment Cancelled';
              body = `Your appointment ${apt.appointment_id} has been cancelled.`;
            }

            await sendPushNotification(userIds, title, body, {
              type: 'appointment-status',
              appointmentId: String(apt.id),
              status: status
            });
          }
        } catch (pushErr) {
          console.error('Error sending status push notification:', pushErr);
        }
      }
    }

    res.json(apt);
  } catch (err) {
    console.error('Error in edit appointment:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

// Manual Meeting Link Generation (for Doctors)
app.post('/api/appointments/:id/generate-link', authenticate, requireRoles(...CLINICAL_STAFF), async (req: any, res) => {
  const { id } = req.params;

  try {
    const current = await assertAppointmentAccess(req, res, id);
    if (!current) return;
    if (current.meeting_link) {
      const normalized = normalizeJitsiMeetingLink(current.meeting_link);
      if (normalized && normalized !== current.meeting_link) {
        await query('UPDATE appointments SET meeting_link = $1 WHERE id = $2', [normalized, id]);
        current.meeting_link = normalized;
      }
      return res.json(current);
    }

    const meetingLink = createSecureJitsiLink();
    
    await query(
      'UPDATE appointments SET meeting_link = $1, payment_status = $2, is_telemedicine = TRUE WHERE id = $3',
      [meetingLink, 'paid', id]
    );

    const result = await query(
      `SELECT a.*, d.name as doctor_name
       FROM appointments a
       LEFT JOIN doctors d ON a.doctor_id = d.id
       WHERE a.id = $1`,
      [id]
    );

    const apt = result.rows[0];
    if (apt) {
      const scheduledInfo = `${new Date(apt.preferred_date).toLocaleDateString()} at ${apt.preferred_time}`;
      const msg = `Medilynks: your video visit ${apt.appointment_id} is ready for ${scheduledInfo}. Open the app to join.`;
      await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in manual link gen:', e));
    }

    res.json(apt);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

async function markAppointmentPaid(apt: any, paymentRef: string, gateway = 'paystack') {
  let meetingLink = normalizeJitsiMeetingLink(apt.meeting_link) || null;
  if (apt.is_telemedicine) {
    meetingLink = meetingLink || createSecureJitsiLink();
  }

  await query(
    `UPDATE appointments
     SET payment_status = 'paid', payment_ref = $1, meeting_link = $2, status = 'approved'
     WHERE id = $3`,
    [paymentRef, meetingLink, apt.id]
  );

  let doctorUserId: number | null = null;
  if (apt.doctor_id) {
    const doc = await query('SELECT user_id FROM doctors WHERE id = $1', [apt.doctor_id]);
    doctorUserId = doc.rows[0]?.user_id || null;
  }
  const billed = await recordVisitPayment(
    Number(apt.id),
    apt.patient_id || null,
    doctorUserId,
    paymentRef,
    gateway
  ).catch((e) => {
    console.error('Coverage payment row failed:', e);
    return { paymentRef, eligibility: { copay: 50, source: 'self_pay' } };
  });

  if (apt.is_telemedicine && meetingLink) {
    const scheduledInfo = `${new Date(apt.preferred_date).toLocaleDateString()} at ${apt.preferred_time}`;
    await sendSMS(
      apt.phone_number,
      `Medilynks: payment confirmed for your visit on ${scheduledInfo}. Open the app to join.`
    ).catch((e) => console.error('SMS Error after pay:', e));
  }

  return { billed, meetingLink };
}

app.post('/api/appointments/:id/pay/initialize', authenticate, async (req: any, res) => {
  const { id } = req.params;
  try {
    const apt = await assertAppointmentAccess(req, res, id);
    if (!apt) return;
    if (apt.payment_status === 'paid') {
      return res.json({
        alreadyProcessed: true,
        paymentRef: apt.payment_ref,
        meetingLink: apt.meeting_link,
      });
    }

    const elig = await getEligibility(apt.patient_id || 0);
    const amountGhs = Number(elig.copay);
    if (!Number.isFinite(amountGhs) || amountGhs < 1) {
      const { billed, meetingLink } = await markAppointmentPaid(apt, `COVER-${apt.id}`, 'coverage');
      return res.json({
        alreadyProcessed: true,
        paymentRef: billed.paymentRef,
        meetingLink,
        eligibility: billed.eligibility,
        message: 'No copay due. Visit is covered.',
      });
    }

    const user = await query('SELECT id, email, phone_number FROM users WHERE id = $1', [req.user.id]);
    const checkout = await initializePaystackCheckout({
      amountGhs,
      email: paystackPaymentEmail({
        id: req.user.id,
        email: user.rows[0]?.email || apt.email,
        phone: user.rows[0]?.phone_number || apt.phone_number,
      }),
      appointmentId: Number(id),
      patientId: apt.patient_id || null,
      userId: Number(req.user.id),
    });

    res.json({
      reference: checkout.reference,
      authorization_url: checkout.authorizationUrl,
      access_code: checkout.accessCode,
      amount: checkout.amountGhs,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Could not start payment';
    console.error('Paystack initialize error:', message);
    const status = message.includes('not configured') ? 503 : 400;
    res.status(status).json({ message });
  }
});

app.post('/api/appointments/:id/pay', authenticate, async (req: any, res) => {
  const { id } = req.params;
  const reference = typeof req.body?.reference === 'string' ? req.body.reference.trim() : '';
  if (!reference) {
    return res.status(400).json({ message: 'Payment reference is required' });
  }

  try {
    const apt = await assertAppointmentAccess(req, res, id);
    if (!apt) return;
    if (apt.payment_status === 'paid') {
      return res.json({
        alreadyProcessed: true,
        paymentRef: apt.payment_ref,
        meetingLink: apt.meeting_link,
      });
    }

    const verified = await verifyPaystackTransaction(reference);
    if (verified.currency && verified.currency !== 'GHS') {
      return res.status(400).json({ message: `Unexpected currency: ${verified.currency}` });
    }

    const elig = await getEligibility(apt.patient_id || 0);
    if (Math.abs(verified.amountGhs - Number(elig.copay)) > 0.05) {
      return res.status(400).json({
        message: `Paid amount GHS ${verified.amountGhs} does not match copay GHS ${elig.copay}`,
      });
    }

    const { billed, meetingLink } = await markAppointmentPaid(apt, verified.reference, 'paystack');
    res.json({
      message: 'Payment confirmed.',
      paymentRef: billed.paymentRef || verified.reference,
      meetingLink,
      eligibility: billed.eligibility,
      alreadyProcessed: (billed as { alreadyProcessed?: boolean }).alreadyProcessed || false,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Payment processing failed';
    console.error('Paystack verify error:', message);
    const status = message.includes('not configured') ? 503 : 400;
    res.status(status).json({ message });
  }
});

app.patch('/api/appointments/:id/status', authenticate, async (req: any, res) => {
  const { id } = req.params;
  const { status } = req.body;
  try {
    const aptData = await assertAppointmentAccess(req, res, id);
    if (!aptData) return;
    if (req.user.role === 'patient' && status !== 'cancelled') {
      return res.status(403).json({ message: 'Forbidden' });
    }

    let meetingLink = normalizeJitsiMeetingLink(aptData?.meeting_link);

    // 2. If starting/approving a video consult that doesn't have a link yet, generate one
    if ((status === 'approved' || status === 'consulting') && !meetingLink &&
        (aptData?.is_telemedicine || aptData?.booking_type === 'consult_now')) {
      meetingLink = createSecureJitsiLink();
    }

    const result = await query(
      `UPDATE appointments 
       SET status = $1::varchar, 
           meeting_link = COALESCE($2, meeting_link),
           completed_at = CASE WHEN $1::varchar = 'completed' THEN CURRENT_TIMESTAMP ELSE completed_at END 
       WHERE id = $3 RETURNING *`,
      [status, meetingLink, id]
    );
    const apt = result.rows[0];
    console.log(`[STATUS UPDATE] Appointment ${id} status set to ${status}. Data:`, apt ? 'found' : 'not found');

    // Status SMS Alerts
    if (apt) {
      if (status === 'approved') {
        const docResult = await query('SELECT name FROM doctors WHERE id = $1', [apt.doctor_id]);
        const doctorName = docResult.rows[0]?.name || 'a Physician';
        const dateStr = apt.preferred_date ? new Date(apt.preferred_date).toLocaleDateString() : 'the scheduled date';
        
        let msg = '';
        if (apt.is_telemedicine && apt.meeting_link) {
          msg = `Medilynks: your video visit ${apt.appointment_id} with ${doctorName} is confirmed for ${dateStr} at ${apt.preferred_time}. Open the app to join.`;
        } else {
          msg = `Medilynks: appointment ${apt.appointment_id} is confirmed with ${doctorName} for ${dateStr}. Open the app for details.`;
        }
        
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Status/Approve:', e));
      } else if (status === 'completed') {
        const docResult = await query('SELECT name FROM doctors WHERE id = $1', [apt.doctor_id]);
        const doctorName = docResult.rows[0]?.name || 'our team';
        const msg = `Medilynks: your visit ${apt.appointment_id} with ${doctorName} is complete. Review your care plan in the app.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Status/Complete:', e));
      } else if (status === 'cancelled') {
        const msg = `Medilynks: appointment ${apt.appointment_id} has been cancelled. Open the app to rebook.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Status/Cancel:', e));
      }

      // Send push notification to the patient
      if (status === 'approved' || status === 'completed' || status === 'cancelled') {
        try {
          const userRes = await query('SELECT id FROM users WHERE phone_number = $1 OR username = $2', [apt.phone_number, apt.email]);
          const userIds = userRes.rows.map(r => r.id);
          if (userIds.length > 0) {
            let title = 'Appointment Update';
            let body = `Your appointment ${apt.appointment_id} status has been updated to ${status}.`;
            if (status === 'approved') {
              title = 'Appointment Approved';
              body = `Your appointment ${apt.appointment_id} has been approved.`;
            } else if (status === 'completed') {
              title = 'Appointment Completed';
              body = `Your appointment ${apt.appointment_id} has been marked as completed. Thank you!`;
            } else if (status === 'cancelled') {
              title = 'Appointment Cancelled';
              body = `Your appointment ${apt.appointment_id} has been cancelled.`;
            }

            await sendPushNotification(userIds, title, body, {
              type: 'appointment-status',
              appointmentId: String(apt.id),
              status: status
            });
          }
        } catch (pushErr) {
          console.error('Error sending status push notification:', pushErr);
        }
      }
    }

    res.json(apt);
  } catch (err) {
    console.error('Error updating status:', err);
    res.status(500).json({ message: 'Server error', error: String(err) });
  }
});

app.patch('/api/appointments/:id/no-show', authenticate, requireRoles(...CLINICAL_STAFF), async (req: any, res) => {
  const { id } = req.params;
  try {
    // Mark as missed
    await query("UPDATE appointments SET status = 'missed' WHERE id = $1", [id]);
    
    // Increment no-show count for patient
    const aptResult = await query('SELECT patient_id FROM appointments WHERE id = $1', [id]);
    const patientId = aptResult.rows[0]?.patient_id;
    
    if (patientId) {
      const updateResult = await query(`
        UPDATE patients 
        SET no_show_count = no_show_count + 1,
            is_restricted = CASE WHEN no_show_count + 1 >= 3 THEN TRUE ELSE FALSE END
        WHERE id = $1 RETURNING *
      `, [patientId]);
      
      res.json({ message: 'Marked as no-show', patient: updateResult.rows[0] });
    } else {
      res.json({ message: 'Marked as no-show' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Notification Routes ---
app.post('/api/push/fcm-token', authenticate, async (req: any, res) => {
  const { token, platform } = req.body;
  const userId = req.user.id;
  try {
    await query(`
      INSERT INTO fcm_tokens (user_id, token, platform, updated_at)
      VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
      ON CONFLICT (user_id, token) 
      DO UPDATE SET platform = $3, updated_at = CURRENT_TIMESTAMP
    `, [userId, token, platform]);
    res.json({ message: 'Token registered successfully' });
  } catch (err) {
    console.error('Error registering FCM token:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/notifications', authenticate, async (req: any, res) => {
  try {
    const result = await query(
      `SELECT * FROM notifications
       WHERE user_id = $1 OR (user_id IS NULL AND $2 = 'admin')
       ORDER BY created_at DESC LIMIT 40`,
      [req.user.id, req.user.role]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/notifications/read', authenticate, async (req: any, res) => {
  try {
    await query('UPDATE notifications SET is_read = TRUE WHERE user_id = $1', [req.user.id]);
    res.json({ message: 'Notifications marked as read' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Prescription Routes ---
app.get('/api/prescriptions', authenticate, async (req: any, res) => {
  try {
    if (req.user.role === 'patient') {
      const patient = await getPatientForUser(req.user.id);
      if (!patient) return res.json([]);
      const result = await query(`
        SELECT pr.*, a.appointment_id as apt_code, p.full_name as patient_name, o.name as pharmacy_name
        FROM prescriptions pr
        JOIN appointments a ON pr.appointment_id = a.id
        JOIN patients p ON pr.patient_id = p.id
        LEFT JOIN partner_orgs o ON pr.pharmacy_id = o.id
        WHERE pr.patient_id = $1
        ORDER BY pr.created_at DESC
      `, [patient.id]);
      return res.json(result.rows);
    }
    if (!['doctor', 'admin', 'medical_ops', 'nurse', 'pharmacy'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    const result = await query(`
      SELECT pr.*, a.appointment_id as apt_code, p.full_name as patient_name, o.name as pharmacy_name
      FROM prescriptions pr
      JOIN appointments a ON pr.appointment_id = a.id
      JOIN patients p ON pr.patient_id = p.id
      LEFT JOIN partner_orgs o ON pr.pharmacy_id = o.id
      ORDER BY pr.created_at DESC
    `);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/prescriptions/my', authenticate, async (req: any, res) => {
  try {
    const patient = await getPatientForUser(req.user.id);
    const patientId = patient?.id;

    if (!patientId) return res.json([]);

    const result = await query(`
      SELECT pr.*, a.appointment_id as apt_code, o.name as pharmacy_name
      FROM prescriptions pr
      JOIN appointments a ON pr.appointment_id = a.id
      LEFT JOIN partner_orgs o ON pr.pharmacy_id = o.id
      WHERE pr.patient_id = $1
      ORDER BY pr.created_at DESC
    `, [patientId]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/prescriptions', authenticate, async (req: any, res) => {
  if (req.user.role === 'patient') return res.status(403).json({ message: 'Forbidden' });
  
  const { appointment_id, patient_id, consultation_id, medication_name, dosage, frequency, duration, instructions, strength, route, quantity } = req.body;
  try {
    const resolvedPatientId = await resolvePatientIdFromAppointment(appointment_id, patient_id);
    const prescriptionRef = 'RX-' + Date.now().toString(36).toUpperCase() + '-' + Math.random().toString(36).substring(2, 5).toUpperCase();
    const result = await query(`
      INSERT INTO prescriptions (appointment_id, patient_id, consultation_id, medication_name, dosage, frequency, duration, instructions, prescription_ref, strength, route, quantity)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING *
    `, [appointment_id, resolvedPatientId, consultation_id || null, medication_name, dosage, frequency, duration, instructions, prescriptionRef, strength || null, route || null, quantity || null]);
    
    const aptResult = await query('SELECT phone_number FROM appointments WHERE id = $1', [appointment_id]);
    if (aptResult.rows[0]) {
      await sendSMS(aptResult.rows[0].phone_number, `Medilynks: a new prescription is ready in your app. Open Prescriptions to review instructions.`);
    }

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.delete('/api/prescriptions/:id', authenticate, async (req: any, res) => {
  if (req.user.role === 'patient') return res.status(403).json({ message: 'Forbidden' });
  try {
    await query('DELETE FROM prescriptions WHERE id = $1', [req.params.id]);
    res.json({ message: 'Prescription deleted' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Consultation Routes ---
app.get('/api/consultations/my', authenticate, async (req: any, res) => {
  if (req.user.role !== 'patient') return res.status(403).json({ message: 'Forbidden' });
  try {
    const patient = await getPatientForUser(req.user.id);
    if (!patient) return res.json([]);
    const result = await query(`
      SELECT c.*, u.name as doctor_name, a.preferred_date, a.service, a.notes as appointment_notes
      FROM consultations c
      JOIN appointments a ON c.appointment_id = a.id
      LEFT JOIN users u ON c.doctor_id = u.id
      WHERE c.patient_id = $1 AND c.status = 'completed'
      ORDER BY c.created_at DESC
    `, [patient.id]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/consultations/:appointmentId', authenticate, async (req: any, res) => {
  try {
    const apt = await assertAppointmentAccess(req, res, req.params.appointmentId);
    if (!apt) return;
    const result = await query(`
      SELECT c.*, u.name as doctor_name
      FROM consultations c
      LEFT JOIN users u ON c.doctor_id = u.id
      WHERE c.appointment_id = $1
      ORDER BY c.created_at DESC
    `, [req.params.appointmentId]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/consultations', authenticate, async (req: any, res) => {
  if (req.user.role !== 'doctor' && req.user.role !== 'admin' && req.user.role !== 'nurse') {
    return res.status(403).json({ message: 'Only clinicians can create consultations' });
  }
  const { appointment_id, patient_id, chief_complaint, symptoms, diagnosis, clinical_notes,
    vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2,
    follow_up_date, status, hpc, medical_history, working_diagnosis, differential, treatment_plan, patient_education } = req.body;
  try {
    const resolvedPatientId = await resolvePatientIdFromAppointment(appointment_id, patient_id);
    const result = await query(`
      INSERT INTO consultations (appointment_id, patient_id, doctor_id, chief_complaint, symptoms, diagnosis, clinical_notes,
        vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2, follow_up_date, status,
        hpc, medical_history, working_diagnosis, differential, treatment_plan, patient_education, started_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, CURRENT_TIMESTAMP) RETURNING *
    `, [appointment_id, resolvedPatientId, req.user.id, chief_complaint, symptoms, diagnosis, clinical_notes,
      vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2, follow_up_date || null, status || 'in_progress',
      hpc || null, medical_history || null, working_diagnosis || diagnosis || null, differential || null, treatment_plan || null, patient_education || null]);
    
    if (status === 'completed' && diagnosis) {
      const aptResult = await query('SELECT phone_number FROM appointments WHERE id = $1', [appointment_id]);
      if (aptResult.rows[0]) {
        await sendSMS(aptResult.rows[0].phone_number, `Medilynks: your consultation is complete. Open the app to review your care plan and prescriptions.`);
      }
    }

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.put('/api/consultations/:id', authenticate, async (req: any, res) => {
  const { chief_complaint, symptoms, diagnosis, clinical_notes,
    vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2,
    follow_up_date, status, hpc, medical_history, working_diagnosis, differential, treatment_plan, patient_education } = req.body;
  try {
    const oldCons = await query('SELECT status, appointment_id FROM consultations WHERE id = $1', [req.params.id]);
    
    const result = await query(`
      UPDATE consultations SET chief_complaint=$1, symptoms=$2, diagnosis=$3, clinical_notes=$4,
        vitals_bp=$5, vitals_temp=$6, vitals_pulse=$7, vitals_weight=$8, vitals_height=$9, vitals_spo2=$10,
        follow_up_date=$11, status=$12,
        hpc=COALESCE($13, hpc), medical_history=COALESCE($14, medical_history),
        working_diagnosis=COALESCE($15, working_diagnosis), differential=COALESCE($16, differential),
        treatment_plan=COALESCE($17, treatment_plan), patient_education=COALESCE($18, patient_education),
        ended_at = CASE WHEN $12 = 'completed' THEN CURRENT_TIMESTAMP ELSE ended_at END
      WHERE id=$19 RETURNING *
    `, [chief_complaint, symptoms, diagnosis, clinical_notes,
      vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2,
      follow_up_date || null, status || 'in_progress',
      hpc || null, medical_history || null, working_diagnosis || diagnosis || null, differential || null,
      treatment_plan || null, patient_education || null, req.params.id]);
    
    if (status === 'completed' && oldCons.rows[0]?.status !== 'completed' && diagnosis) {
      const aptResult = await query('SELECT phone_number FROM appointments WHERE id = $1', [oldCons.rows[0].appointment_id]);
      if (aptResult.rows[0]) {
        await sendSMS(aptResult.rows[0].phone_number, `Medilynks: your consultation is complete. Open the app to review your care plan and prescriptions.`);
      }
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Lab Request Routes ---
app.get('/api/labs', authenticate, async (req: any, res) => {
  try {
    const { patient_id, status } = req.query;
    let sql = `
      SELECT lr.*, a.full_name as patient_name, a.appointment_id as apt_code, u.name as doctor_name,
             o.name as partner_name
      FROM lab_requests lr
      LEFT JOIN appointments a ON lr.appointment_id = a.id
      LEFT JOIN users u ON lr.doctor_id = u.id
      LEFT JOIN partner_orgs o ON lr.partner_id = o.id
    `;
    const conditions: string[] = [];
    const params: any[] = [];
    
    if (req.user.role === 'patient') {
      const patient = await getPatientForUser(req.user.id);
      if (!patient) return res.json([]);
      conditions.push(`lr.patient_id = $${params.length + 1}`);
      params.push(patient.id);
    } else if (patient_id) {
      if (!(await canAccessPatient(req.user, patient_id))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      conditions.push(`lr.patient_id = $${params.length + 1}`);
      params.push(patient_id);
    } else if (!['doctor', 'admin', 'medical_ops', 'nurse', 'lab_technician'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    if (status) { conditions.push(`lr.status = $${params.length + 1}`); params.push(status); }
    if (req.user.role === 'lab_technician') {
      const staff = await query(
        `SELECT o.id FROM partner_orgs o JOIN partner_staff s ON s.org_id = o.id
         WHERE s.user_id = $1 AND o.type = 'laboratory' LIMIT 1`,
        [req.user.id]
      );
      if (staff.rows[0]) {
        conditions.push(`(lr.partner_id = $${params.length + 1} OR lr.partner_id IS NULL)`);
        params.push(staff.rows[0].id);
      }
    }
    
    if (conditions.length > 0) sql += ' WHERE ' + conditions.join(' AND ');
    sql += ' ORDER BY lr.created_at DESC';
    
    const result = await query(sql, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/labs', authenticate, async (req: any, res) => {
  if (req.user.role !== 'doctor' && req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Only doctors can order labs' });
  }
  const { consultation_id, appointment_id, patient_id, test_name, test_type, urgency } = req.body;
  try {
    const resolvedPatientId = await resolvePatientIdFromAppointment(appointment_id, patient_id);
    // Get doctor name
    const userResult = await query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    const doctorName = userResult.rows[0]?.name || 'Unknown';
    
    const nearest = await assignNearestPartner('laboratory', resolvedPatientId);
    const result = await query(`
      INSERT INTO lab_requests (consultation_id, appointment_id, patient_id, doctor_id, test_name, test_type, urgency, requested_by, partner_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *
    `, [consultation_id || null, appointment_id, resolvedPatientId, req.user.id, test_name, test_type || 'blood', urgency || 'routine', doctorName, nearest?.id || null]);
    res.status(201).json({ ...result.rows[0], partner_name: nearest?.name || null });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.put('/api/labs/:id', authenticate, async (req: any, res) => {
  // Lab technicians, doctors, and admins can update
  if (!['lab_technician', 'doctor', 'admin'].includes(req.user.role)) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  const { status, results, result_notes } = req.body;
  try {
    const userResult = await query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    const completedBy = userResult.rows[0]?.name || 'Unknown';
    
    const result = await query(`
      UPDATE lab_requests SET status=$1, results=$2, result_notes=$3, 
        completed_by=$4,
        completed_at=${status === 'completed' ? 'CURRENT_TIMESTAMP' : 'completed_at'},
        result_returned_at=${status === 'completed' ? 'CURRENT_TIMESTAMP' : 'result_returned_at'}
      WHERE id=$5 RETURNING *
    `, [status, results, result_notes, completedBy, req.params.id]);
    if (status === 'completed' && result.rows[0]) {
      await notifyDiagnosticClosedLoop(
        { sendSMS, sendPushNotification },
        result.rows[0],
        'lab'
      );
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Scan Request Routes ---
app.get('/api/scans', authenticate, async (req: any, res) => {
  try {
    const { patient_id, status } = req.query;
    let sql = `
      SELECT sr.*, a.full_name as patient_name, a.appointment_id as apt_code, u.name as doctor_name,
             o.name as partner_name
      FROM scan_requests sr
      LEFT JOIN appointments a ON sr.appointment_id = a.id
      LEFT JOIN users u ON sr.doctor_id = u.id
      LEFT JOIN partner_orgs o ON sr.partner_id = o.id
    `;
    const conditions: string[] = [];
    const params: any[] = [];
    
    if (req.user.role === 'patient') {
      const patient = await getPatientForUser(req.user.id);
      if (!patient) return res.json([]);
      conditions.push(`sr.patient_id = $${params.length + 1}`);
      params.push(patient.id);
    } else if (patient_id) {
      if (!(await canAccessPatient(req.user, patient_id))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      conditions.push(`sr.patient_id = $${params.length + 1}`);
      params.push(patient_id);
    } else if (!['doctor', 'admin', 'medical_ops', 'nurse', 'imaging', 'lab_technician'].includes(req.user.role)) {
      return res.status(403).json({ message: 'Forbidden' });
    }
    if (status) { conditions.push(`sr.status = $${params.length + 1}`); params.push(status); }
    if (req.user.role === 'imaging' || req.user.role === 'lab_technician') {
      const staff = await query(
        `SELECT o.id FROM partner_orgs o JOIN partner_staff s ON s.org_id = o.id
         WHERE s.user_id = $1 AND o.type = $2 LIMIT 1`,
        [req.user.id, req.user.role === 'imaging' ? 'imaging' : 'laboratory']
      );
      if (staff.rows[0] && req.user.role === 'imaging') {
        conditions.push(`(sr.partner_id = $${params.length + 1} OR sr.partner_id IS NULL)`);
        params.push(staff.rows[0].id);
      }
    }
    
    if (conditions.length > 0) sql += ' WHERE ' + conditions.join(' AND ');
    sql += ' ORDER BY sr.created_at DESC';
    
    const result = await query(sql, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/scans', authenticate, async (req: any, res) => {
  if (req.user.role !== 'doctor' && req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Only doctors can request scans' });
  }
  const { consultation_id, appointment_id, patient_id, scan_type, body_part, clinical_indication, urgency } = req.body;
  try {
    const resolvedPatientId = await resolvePatientIdFromAppointment(appointment_id, patient_id);
    const userResult = await query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    const doctorName = userResult.rows[0]?.name || 'Unknown';
    
    const nearest = await assignNearestPartner('imaging', resolvedPatientId);
    const result = await query(`
      INSERT INTO scan_requests (consultation_id, appointment_id, patient_id, doctor_id, scan_type, body_part, clinical_indication, urgency, requested_by, partner_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *
    `, [consultation_id || null, appointment_id, resolvedPatientId, req.user.id, scan_type, body_part, clinical_indication, urgency || 'routine', doctorName, nearest?.id || null]);
    res.status(201).json({ ...result.rows[0], partner_name: nearest?.name || null });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.put('/api/scans/:id', authenticate, async (req: any, res) => {
  if (!['lab_technician', 'imaging', 'doctor', 'admin'].includes(req.user.role)) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  const { status, results, result_notes } = req.body;
  try {
    const userResult = await query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    const completedBy = userResult.rows[0]?.name || 'Unknown';
    
    const result = await query(`
      UPDATE scan_requests SET status=$1, results=$2, result_notes=$3,
        completed_by=$4,
        completed_at=${status === 'completed' ? 'CURRENT_TIMESTAMP' : 'completed_at'},
        result_returned_at=${status === 'completed' ? 'CURRENT_TIMESTAMP' : 'result_returned_at'}
      WHERE id=$5 RETURNING *
    `, [status, results, result_notes, completedBy, req.params.id]);
    if (status === 'completed' && result.rows[0]) {
      await notifyDiagnosticClosedLoop(
        { sendSMS, sendPushNotification },
        result.rows[0],
        'scan'
      );
    }
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Patient History (Aggregated Timeline) ---
app.get('/api/patients/:id/history', authenticate, async (req: any, res) => {
  const patientId = req.params.id;
  if (!(await canAccessPatient(req.user, patientId))) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  try {
    const [consultations, labs, scans, prescriptions] = await Promise.all([
      query(`
        SELECT c.*, u.name as doctor_name, a.full_name as patient_name, a.preferred_date, a.preferred_time
        FROM consultations c
        LEFT JOIN users u ON c.doctor_id = u.id
        LEFT JOIN appointments a ON c.appointment_id = a.id
        WHERE c.patient_id = $1
        ORDER BY c.created_at DESC
      `, [patientId]),
      query(`
        SELECT lr.*, a.full_name as patient_name
        FROM lab_requests lr
        LEFT JOIN appointments a ON lr.appointment_id = a.id
        WHERE lr.patient_id = $1
        ORDER BY lr.created_at DESC
      `, [patientId]),
      query(`
        SELECT sr.*, a.full_name as patient_name
        FROM scan_requests sr
        LEFT JOIN appointments a ON sr.appointment_id = a.id
        WHERE sr.patient_id = $1
        ORDER BY sr.created_at DESC
      `, [patientId]),
      query(`
        SELECT pr.*, a.full_name as patient_name
        FROM prescriptions pr
        LEFT JOIN appointments a ON pr.appointment_id = a.id
        WHERE pr.patient_id = $1
        ORDER BY pr.created_at DESC
      `, [patientId])
    ]);
    
    res.json({
      consultations: consultations.rows,
      labs: labs.rows,
      scans: scans.rows,
      prescriptions: prescriptions.rows
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// Also support history lookup by appointment (for walk-in patients without patient_id)
app.get('/api/appointments/:id/history', authenticate, async (req: any, res) => {
  const appointmentId = req.params.id;
  const apt = await assertAppointmentAccess(req, res, appointmentId);
  if (!apt) return;
  try {
    const [consultations, labs, scans, prescriptions] = await Promise.all([
      query('SELECT c.*, u.name as doctor_name FROM consultations c LEFT JOIN users u ON c.doctor_id = u.id WHERE c.appointment_id = $1 ORDER BY c.created_at DESC', [appointmentId]),
      query('SELECT * FROM lab_requests WHERE appointment_id = $1 ORDER BY created_at DESC', [appointmentId]),
      query('SELECT * FROM scan_requests WHERE appointment_id = $1 ORDER BY created_at DESC', [appointmentId]),
      query('SELECT * FROM prescriptions WHERE appointment_id = $1 ORDER BY created_at DESC', [appointmentId])
    ]);
    
    res.json({
      consultations: consultations.rows,
      labs: labs.rows,
      scans: scans.rows,
      prescriptions: prescriptions.rows
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});


// --- Doctor Routes ---
app.get('/api/doctors', authenticate, async (req, res) => {
  try {
    const result = await query('SELECT * FROM doctors ORDER BY name');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/doctors', authenticate, requireRoles(...ADMIN_OPS), async (req, res) => {
  const { name, specialization, slot_duration, working_days, start_time, end_time, is_active } = req.body;
  try {
    const result = await query(`
      INSERT INTO doctors (name, specialization, slot_duration, working_days, start_time, end_time, is_active)
      VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *
    `, [name, specialization, slot_duration, working_days, start_time, end_time, is_active ?? true]);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.put('/api/doctors/:id', authenticate, requireRoles(...ADMIN_OPS), async (req, res) => {
  const { id } = req.params;
  const { name, specialization, slot_duration, working_days, start_time, end_time, is_active } = req.body;
  try {
    const result = await query(`
      UPDATE doctors 
      SET name = $1, specialization = $2, slot_duration = $3, working_days = $4, start_time = $5, end_time = $6, is_active = $7
      WHERE id = $8 RETURNING *
    `, [name, specialization, slot_duration, working_days, start_time, end_time, is_active, id]);
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/doctors/:id/status', authenticate, requireRoles(...ADMIN_OPS), async (req, res) => {
  const { id } = req.params;
  const { is_active } = req.body;
  try {
    const result = await query(
      'UPDATE doctors SET is_active = $1 WHERE id = $2 RETURNING *',
      [is_active, id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Analytics Routes ---
app.get('/api/analytics/dashboard', authenticate, requireRoles(...CLINICAL_STAFF), async (req: any, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];
    let doctorId = null;

    if (req.user.role === 'doctor') {
      const docResult = await query('SELECT id FROM doctors WHERE user_id = $1', [req.user.id]);
      if (docResult.rows.length > 0) {
        doctorId = docResult.rows[0].id;
      } else {
        // Doctor record not found - return empty stats instead of 403 to avoid logout
        return res.json({
          stats: { total: 0, today: 0, pending: 0, completed: 0 },
          trends: [],
          workload: [],
          noShow: { missed_total: 0, repeated_offenders: 0 },
          peakHours: 'No Data',
          waitDistribution: [
            { label: 'Under 15m', val: 0, color: 'bg-green-500' },
            { label: '15 - 30m', val: 0, color: 'bg-amber-500' },
            { label: 'Over 30m', val: 0, color: 'bg-red-500' }
          ],
          satisfaction: '0.0'
        });
      }
    }

    const doctorFilter = doctorId ? ' AND doctor_id = $2' : '';
    const doctorFilterWhere = doctorId ? ' WHERE doctor_id = $1' : '';
    const doctorFilterWorkload = doctorId ? ' AND d.id = $2' : '';
    const params = doctorId ? [today, doctorId] : [today];
    
    // Stats
    const statsResult = await query(`
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE preferred_date = $1${doctorFilter}) as today,
        COUNT(*) FILTER (WHERE status = 'pending'${doctorFilter}) as pending,
        COUNT(*) FILTER (WHERE status = 'completed'${doctorFilter}) as completed
      FROM appointments
      ${doctorId ? 'WHERE doctor_id = $2' : ''}
    `, params);

    // Weekly Trends
    const trendsResult = await query(`
      SELECT 
        to_char(preferred_date, 'Dy') as day,
        COUNT(*) as count
      FROM appointments
      WHERE preferred_date > CURRENT_DATE - INTERVAL '7 days'${doctorId ? ' AND doctor_id = $1' : ''}
      GROUP BY preferred_date
      ORDER BY preferred_date
    `, doctorId ? [doctorId] : []);

    // Doctor Workload
    const workloadResult = await query(`
      SELECT 
        d.name,
        COUNT(a.id) as count
      FROM doctors d
      LEFT JOIN appointments a ON d.id = a.doctor_id AND a.preferred_date = $1
      WHERE d.is_active = TRUE${doctorFilterWorkload}
      GROUP BY d.id, d.name
    `, params);

    // No-Show Stats
    const noShowResult = await query(`
      SELECT 
        COUNT(*) FILTER (WHERE status = 'missed') as missed_total,
        COUNT(DISTINCT patient_id) FILTER (WHERE status = 'missed') as repeated_offenders
      FROM appointments
      ${doctorFilterWhere}
    `, doctorId ? [doctorId] : []);
    
    // Peak Hours
    const peakHoursResult = await query(`
      SELECT 
        extract(hour from preferred_time) as hour,
        COUNT(*) as count
      FROM appointments
      WHERE preferred_date = $1${doctorFilter}
      GROUP BY hour
      ORDER BY count DESC
      LIMIT 1
    `, params);

    let peakRange = 'No Data'; // Improved fallback
    if (peakHoursResult.rows.length > 0) {
      const peakHour = parseInt(peakHoursResult.rows[0].hour);
      peakRange = `${peakHour.toString().padStart(2, '0')}:00 - ${(peakHour + 2).toString().padStart(2, '0')}:00`;
    }

    // Wait Time Distribution
    const waitTimeResult = await query(`
      SELECT 
        COUNT(*) FILTER (WHERE wait_mins < 15) as under_15,
        COUNT(*) FILTER (WHERE wait_mins >= 15 AND wait_mins <= 30) as between_15_30,
        COUNT(*) FILTER (WHERE wait_mins > 30) as over_30,
        COUNT(*) as total
      FROM (
        SELECT 
          EXTRACT(EPOCH FROM (completed_at - (preferred_date + preferred_time))) / 60 as wait_mins
        FROM appointments
        WHERE status = 'completed' AND completed_at IS NOT NULL${doctorId ? ' AND doctor_id = $1' : ''}
      ) as sub
    `, doctorId ? [doctorId] : []);

    let waitDistribution = [
      { label: 'Under 15m', val: 0, color: 'bg-green-500' },
      { label: '15 - 30m', val: 0, color: 'bg-amber-500' },
      { label: 'Over 30m', val: 0, color: 'bg-red-500' }
    ];

    if (waitTimeResult.rows[0].total > 0 && parseInt(waitTimeResult.rows[0].total) > 0) {
      const total = parseInt(waitTimeResult.rows[0].total);
      waitDistribution = [
        { label: 'Under 15m', val: Math.round((parseInt(waitTimeResult.rows[0].under_15) / total) * 100), color: 'bg-green-500' },
        { label: '15 - 30m', val: Math.round((parseInt(waitTimeResult.rows[0].between_15_30) / total) * 100), color: 'bg-amber-500' },
        { label: 'Over 30m', val: Math.round((parseInt(waitTimeResult.rows[0].over_30) / total) * 100), color: 'bg-red-500' }
      ];
    } else {
      // Real empty state instead of dummy data
      waitDistribution = [
        { label: 'Under 15m', val: 0, color: 'bg-green-500' },
        { label: '15 - 30m', val: 0, color: 'bg-amber-500' },
        { label: 'Over 30m', val: 0, color: 'bg-red-500' }
      ];
    }
    
    // Satisfaction (Simulated based on completion rate for now)
    const completionRate = statsResult.rows[0].total > 0 
      ? (statsResult.rows[0].completed / statsResult.rows[0].total) 
      : 0.95;
    const satisfaction = (4.0 + (completionRate * 1.0)).toFixed(1);

    res.json({
      stats: statsResult.rows[0],
      trends: trendsResult.rows,
      workload: workloadResult.rows,
      noShow: noShowResult.rows[0],
      peakHours: peakRange,
      waitDistribution,
      satisfaction
    });
  } catch (err: any) {
    console.error(err);
    import('fs').then(fs => fs.writeFileSync('error_log.txt', String(err) + '\n' + String(err.stack)));
    res.status(500).json({ message: 'Server error', error: String(err) });
  }
});

registerPhase1Routes(app, { authenticate, sendSMS, sendPushNotification });
registerPhase2Routes(app, { authenticate, sendSMS, sendPushNotification });
registerPhase3Routes(app, { authenticate, sendSMS, sendPushNotification });
registerClinicalRoutes(app);
registerPhase4Routes(app);
registerPhase5Routes(app);
registerCompleteRoutes(app);
registerMembershipRoutes(app, authenticate);
registerPhaseOverviewRoutes(app);

// Initialize Database
initDb().then(() => {
  app.listen(Number(PORT), '0.0.0.0', () => {
    console.log(`Server running on port ${PORT}`);
  });
}).catch(err => {
  console.error('Failed to initialize database:', err);
  process.exit(1);
});

// Keep the process alive
setInterval(() => {}, 1000);
