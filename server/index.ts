import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { initDb, query } from './db';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import axios from 'axios';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// --- Middleware ---
const authenticate = (req: any, res: any, next: any) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ message: 'No token provided' });

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET!);
    req.user = decoded;
    next();
  } catch (err) {
    res.status(401).json({ message: 'Invalid token' });
  }
};

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'telemedicine-api' });
});

// Initialize Database
initDb();

// --- Auth Routes ---
app.post('/api/auth/login', async (req, res) => {
  const { username, password } = req.body;
  try {
    const result = await query('SELECT * FROM users WHERE username = $1', [username]);
    const user = result.rows[0];

    if (user && await bcrypt.compare(password, user.password)) {
      const token = jwt.sign(
        { id: user.id, username: user.username, role: user.role },
        process.env.JWT_SECRET!,
        { expiresIn: '24h' }
      );
      res.json({ token, user: { id: user.id, username: user.username, role: user.role, name: user.name } });
    } else {
      res.status(401).json({ message: 'Invalid credentials' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/auth/register', async (req, res) => {
  const { username, password, name, phone_number, email } = req.body;
  try {
    // Check if user exists
    const checkUser = await query('SELECT * FROM users WHERE username = $1', [username]);
    if (checkUser.rows.length > 0) {
      return res.status(400).json({ message: 'Username already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    
    // Create User
    const userResult = await query(
      'INSERT INTO users (username, password, role, name, phone_number) VALUES ($1, $2, $3, $4, $5) RETURNING id, username, role',
      [username, hashedPassword, 'patient', name, phone_number]
    );
    const user = userResult.rows[0];

    // Create Patient Profile
    await query(
      'INSERT INTO patients (full_name, email, phone_number) VALUES ($1, $2, $3)',
      [name, email, phone_number]
    );

    const token = jwt.sign(
      { id: user.id, username: user.username, role: user.role },
      process.env.JWT_SECRET!,
      { expiresIn: '24h' }
    );

    res.status(201).json({ 
      token, 
      user: { id: user.id, username: user.username, role: user.role, name } 
    });
  } catch (err) {
    console.error('Registration error:', err);
    res.status(500).json({ message: 'Server error during registration' });
  }
});



app.post('/api/auth/forgot-password', async (req, res) => {
  const { username } = req.body;
  try {
    const userResult = await query('SELECT * FROM users WHERE username = $1', [username]);
    const user = userResult.rows[0];

    if (!user || !user.phone_number) {
      return res.status(404).json({ message: 'User not found or no phone number registered.' });
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 10 * 60000); // 10 mins

    await query('DELETE FROM otps WHERE username = $1', [username]);
    await query('INSERT INTO otps (username, code, expires_at) VALUES ($1, $2, $3)', [username, otp, expiresAt]);

    await sendSMS(user.phone_number, `Your CSA Health Portal password reset code is: ${otp}. It expires in 10 minutes.`);

    res.json({ message: 'OTP sent to registered phone number.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/auth/reset-password', async (req, res) => {
  const { username, code, newPassword } = req.body;
  try {
    const otpResult = await query('SELECT * FROM otps WHERE username = $1 AND code = $2 AND expires_at > NOW()', [username, code]);
    
    if (otpResult.rows.length === 0) {
      return res.status(400).json({ message: 'Invalid or expired OTP.' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await query('UPDATE users SET password = $1 WHERE username = $2', [hashedPassword, username]);
    await query('DELETE FROM otps WHERE username = $1', [username]);

    res.json({ message: 'Password reset successful.' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Settings Routes ---
app.get('/api/settings', async (req, res) => {
  try {
    const result = await query('SELECT * FROM settings');
    const settings = result.rows.reduce((acc: any, row: any) => {
      acc[row.key] = row.value;
      return acc;
    }, {});
    res.json(settings);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/settings', async (req, res) => {
  const updates = req.body;
  try {
    for (const [key, value] of Object.entries(updates)) {
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
app.get('/api/users', async (req, res) => {
  try {
    const result = await query('SELECT id, username, role, name, phone_number FROM users ORDER BY name');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/users', async (req, res) => {
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

app.put('/api/users/:id', async (req, res) => {
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

app.delete('/api/users/:id', async (req, res) => {
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
      // Find the doctor_id for this user
      const docResult = await query('SELECT id FROM doctors WHERE user_id = $1', [req.user.id]);
      if (docResult.rows.length > 0) {
        queryText += ' WHERE a.doctor_id = $1';
        queryParams.push(docResult.rows[0].id);
      } else {
        // If doctor not found in doctors table, return empty
        return res.json([]);
      }
    }

    queryText += ' ORDER BY a.preferred_date DESC, a.preferred_time DESC';
    
    const result = await query(queryText, queryParams);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/appointments/my', authenticate, async (req: any, res) => {
  try {
    // Get patient_id from user table or by matching phone number
    const userResult = await query('SELECT phone_number FROM users WHERE id = $1', [req.user.id]);
    const phone = userResult.rows[0].phone_number;

    const result = await query(`
      SELECT a.*, d.name as doctor_name 
      FROM appointments a 
      LEFT JOIN doctors d ON a.doctor_id = d.id 
      WHERE a.phone_number = $1
      ORDER BY a.preferred_date DESC, a.preferred_time DESC
    `, [phone]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/appointments', async (req, res) => {
  const { 
    fullName, whoIsComing, phoneNumber, email, staffId, nationwideId, department, 
    reason, preferredDate, preferredTime, priority, notes, doctor_id, service, isTelemedicine
  } = req.body;
  
  const effectiveStaffId = staffId || null;
  
  try {
    // 1. Check if patient exists (by staffId if available, else by phoneNumber)
    let patientResult;
    if (effectiveStaffId) {
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

    const appointmentId = 'APT-' + Math.random().toString(36).substring(2, 9).toUpperCase();

    const result = await query(`
      INSERT INTO appointments (
        appointment_id, patient_id, full_name, who_is_coming, phone_number, email, staff_id, nationwide_id,
        department, notes, preferred_date, preferred_time, priority, doctor_id, service, is_telemedicine
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
      RETURNING *
    `, [
      appointmentId, patient.id, fullName, whoIsComing, phoneNumber, email, staffId, nationwideId,
      department, reason + (notes ? ' | ' + notes : ''), preferredDate, preferredTime, priority, doctor_id, service, !!isTelemedicine
    ]);

    if (doctor_id && req.user?.role === 'patient') {
      const docResult = await query('SELECT user_id FROM doctors WHERE id = $1', [doctor_id]);
      const doctorUserId = docResult.rows[0]?.user_id;
      if (doctorUserId) {
        await query(`
          INSERT INTO chat_threads (patient_user_id, doctor_user_id)
          VALUES ($1, $2)
          ON CONFLICT (patient_user_id, doctor_user_id) DO NOTHING
        `, [req.user.id, doctorUserId]);
      }
    }

    // Real SMS Sending
    const locationLink = "https://www.google.com/maps/search/?api=1&query=Primecare+Medical+Center+Accra";
    await sendSMS(phoneNumber, `CSA: Your appointment ${appointmentId} is booked for ${preferredDate} at ${preferredTime}. Location: ${locationLink}. Thank you for choosing Primecare Medical Center.`);
    
    
    // Admin Alerts
    console.log(`Admin Alert: New appointment ${appointmentId} booked by ${fullName}.`);
    
    // Send SMS to Admin
    await sendSMS('+233200024081', `Admin Alert: New appointment ${appointmentId} booked by ${fullName} for ${preferredDate} at ${preferredTime}.`).catch(e => console.error('Admin SMS Error:', e));

    await query('INSERT INTO notifications (message) VALUES ($1)', [
      `New appointment booked: ${appointmentId} by ${fullName}`
    ]);

    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/appointments/:id', async (req, res) => {
  const { id } = req.params;
  const { preferred_date, preferred_time, notes, doctor_id, priority, status, who_is_coming, service, is_telemedicine } = req.body;
  try {
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
        const locationLink = "https://www.google.com/maps/search/?api=1&query=Primecare+Medical+Center+Accra";
        const msg = `CSA: Your appointment ${apt.appointment_id} has been APPROVED with ${doctorName} for ${dateStr}. Location: ${locationLink}. Call +233200024081 for enquiries. Thank you for choosing Primecare Medical Center.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Edit/Approve:', e));
      } else if (status === 'completed') {
        const docResult = await query('SELECT name FROM doctors WHERE id = $1', [apt.doctor_id]);
        const doctorName = docResult.rows[0]?.name || 'our team';
        const msg = `CSA: Your appointment ${apt.appointment_id} with ${doctorName} has been marked as COMPLETED. Call +233200024081 for enquiries. Thank you for choosing Primecare Medical Center.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Edit/Complete:', e));
      } else if (status === 'cancelled') {
        const msg = `CSA: Your appointment ${apt.appointment_id} has been CANCELLED. Call +233200024081 for enquiries. Thank you for choosing Primecare Medical Center.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Edit/Cancel:', e));
      }
    }

    res.json(apt);
  } catch (err) {
    console.error('Error in edit appointment:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

// Manual Meeting Link Generation (for Doctors)
app.post('/api/appointments/:id/generate-link', authenticate, async (req: any, res) => {
  const { id } = req.params;
  if (req.user.role === 'patient') return res.status(403).json({ message: 'Forbidden' });

  try {
    // Generate a "real" looking Google Meet code: abc-defg-hij
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    const getChars = (len: number) => Array.from({length: len}, () => chars[Math.floor(Math.random() * chars.length)]).join('');
    const meetingLink = `https://meet.jit.si/graprime-telemed-${getChars(3)}-${getChars(4)}-${getChars(3)}`;
    
    const result = await query(
      'UPDATE appointments SET meeting_link = $1, payment_status = $2 WHERE id = $3 RETURNING *',
      [meetingLink, 'paid', id]
    );

    const apt = result.rows[0];
    if (apt) {
      // Include date and time in the SMS
      const scheduledInfo = `${new Date(apt.preferred_date).toLocaleDateString()} at ${apt.preferred_time}`;
      const msg = `CSA: Your Telemedicine session link for ${apt.appointment_id} is ready: ${meetingLink}. Scheduled for ${scheduledInfo}. Please join at your scheduled time. Thank you.`;
      await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in manual link gen:', e));
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/appointments/:id/pay', authenticate, async (req: any, res) => {
  const { id } = req.params;
  try {
    const aptResult = await query('SELECT * FROM appointments WHERE id = $1', [id]);
    const apt = aptResult.rows[0];

    if (!apt) return res.status(404).json({ message: 'Appointment not found' });

    const paymentRef = 'PAY-' + Math.random().toString(36).substring(2, 10).toUpperCase();
    const status = 'paid'; 
    
    let meetingLink = null;
    if (apt.is_telemedicine) {
      const chars = 'abcdefghijklmnopqrstuvwxyz';
      const getChars = (len: number) => Array.from({length: len}, () => chars[Math.floor(Math.random() * chars.length)]).join('');
      meetingLink = `https://meet.jit.si/graprime-telemed-${getChars(3)}-${getChars(4)}-${getChars(3)}`;
    }

    await query(`
      UPDATE appointments 
      SET payment_status = $1, 
          payment_ref = $2, 
          meeting_link = $3,
          status = 'approved'
      WHERE id = $4
    `, [status, paymentRef, meetingLink, id]);

    if (apt.is_telemedicine && meetingLink) {
      const scheduledInfo = `${new Date(apt.preferred_date).toLocaleDateString()} at ${apt.preferred_time}`;
      await sendSMS(apt.phone_number, `CSA: Payment Confirmed! Your session with the doctor for ${scheduledInfo} is set. Join here: ${meetingLink}`);
    }

    res.json({ message: 'Payment successful', paymentRef, meetingLink });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Payment processing failed' });
  }
});

app.patch('/api/appointments/:id/status', async (req, res) => {
  const { id } = req.params;
  const { status } = req.body;
  try {
    // 1. Get current appointment data to check telemedicine status
    const initialApt = await query('SELECT * FROM appointments WHERE id = $1', [id]);
    const aptData = initialApt.rows[0];

    let meetingLink = aptData?.meeting_link;

    // 2. If approving a telemedicine appointment that doesn't have a link yet, generate one
    if (status === 'approved' && aptData?.is_telemedicine && !meetingLink) {
      const chars = 'abcdefghijklmnopqrstuvwxyz';
      const getChars = (len: number) => Array.from({length: len}, () => chars[Math.floor(Math.random() * chars.length)]).join('');
      meetingLink = `https://meet.jit.si/graprime-telemed-${getChars(3)}-${getChars(4)}-${getChars(3)}`;
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
          msg = `CSA: Your Telemedicine session ${apt.appointment_id} with ${doctorName} is APPROVED for ${dateStr} at ${apt.preferred_time}. Join link: ${apt.meeting_link}. Thank you for choosing Primecare.`;
        } else {
          const locationLink = "https://www.google.com/maps/search/?api=1&query=Primecare+Medical+Center+Accra";
          msg = `CSA: Your appointment ${apt.appointment_id} has been APPROVED with ${doctorName} for ${dateStr}. Location: ${locationLink}. Call +233200024081 for enquiries. Thank you for choosing Primecare Medical Center.`;
        }
        
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Status/Approve:', e));
      } else if (status === 'completed') {
        const docResult = await query('SELECT name FROM doctors WHERE id = $1', [apt.doctor_id]);
        const doctorName = docResult.rows[0]?.name || 'our team';
        const msg = `CSA: Your appointment ${apt.appointment_id} with ${doctorName} has been marked as COMPLETED. Call +233200024081 for enquiries. Thank you for choosing Primecare Medical Center.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Status/Complete:', e));
      } else if (status === 'cancelled') {
        const msg = `CSA: Your appointment ${apt.appointment_id} has been CANCELLED. Call +233200024081 for enquiries. Thank you for choosing Primecare Medical Center.`;
        await sendSMS(apt.phone_number, msg).catch(e => console.error('SMS Error in Status/Cancel:', e));
      }
    }

    res.json(apt);
  } catch (err) {
    console.error('Error updating status:', err);
    res.status(500).json({ message: 'Server error', error: String(err) });
  }
});

app.patch('/api/appointments/:id/no-show', async (req, res) => {
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
app.get('/api/notifications', async (req, res) => {
  try {
    const result = await query('SELECT * FROM notifications ORDER BY created_at DESC LIMIT 10');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/notifications/read', async (req, res) => {
  try {
    await query('UPDATE notifications SET is_read = TRUE');
    res.json({ message: 'Notifications marked as read' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Prescription Routes ---
app.get('/api/prescriptions', authenticate, async (req: any, res) => {
  try {
    const result = await query(`
      SELECT pr.*, a.appointment_id as apt_code, p.full_name as patient_name 
      FROM prescriptions pr
      JOIN appointments a ON pr.appointment_id = a.id
      JOIN patients p ON pr.patient_id = p.id
      ORDER BY pr.created_at DESC
    `);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/prescriptions/my', authenticate, async (req: any, res) => {
  try {
    const userResult = await query('SELECT phone_number FROM users WHERE id = $1', [req.user.id]);
    const phone = userResult.rows[0].phone_number;
    const patientResult = await query('SELECT id FROM patients WHERE phone_number = $1', [phone]);
    const patientId = patientResult.rows[0]?.id;

    if (!patientId) return res.json([]);

    const result = await query(`
      SELECT pr.*, a.appointment_id as apt_code 
      FROM prescriptions pr
      JOIN appointments a ON pr.appointment_id = a.id
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
  
  const { appointment_id, patient_id, consultation_id, medication_name, dosage, frequency, duration, instructions } = req.body;
  try {
    const result = await query(`
      INSERT INTO prescriptions (appointment_id, patient_id, consultation_id, medication_name, dosage, frequency, duration, instructions)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *
    `, [appointment_id, patient_id, consultation_id || null, medication_name, dosage, frequency, duration, instructions]);
    
    const aptResult = await query('SELECT phone_number FROM appointments WHERE id = $1', [appointment_id]);
    if (aptResult.rows[0]) {
      await sendSMS(aptResult.rows[0].phone_number, `CSA: A new prescription for ${medication_name} has been added to your portal. Please check your Patient Dashboard for dosage instructions.`);
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
    const result = await query(`
      SELECT c.*, u.name as doctor_name, a.preferred_date, a.service, a.notes as appointment_notes
      FROM consultations c
      JOIN appointments a ON c.appointment_id = a.id
      LEFT JOIN users u ON c.doctor_id = u.id
      WHERE c.patient_id = $1 AND c.status = 'completed'
      ORDER BY c.created_at DESC
    `, [req.user.id]);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/consultations/:appointmentId', authenticate, async (req: any, res) => {
  try {
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
  if (req.user.role !== 'doctor' && req.user.role !== 'admin') {
    return res.status(403).json({ message: 'Only doctors can create consultations' });
  }
  const { appointment_id, patient_id, chief_complaint, symptoms, diagnosis, clinical_notes,
    vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2,
    follow_up_date, status } = req.body;
  try {
    const result = await query(`
      INSERT INTO consultations (appointment_id, patient_id, doctor_id, chief_complaint, symptoms, diagnosis, clinical_notes,
        vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2, follow_up_date, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING *
    `, [appointment_id, patient_id, req.user.id, chief_complaint, symptoms, diagnosis, clinical_notes,
      vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2, follow_up_date || null, status || 'in_progress']);
    
    if (status === 'completed' && diagnosis) {
      const aptResult = await query('SELECT phone_number FROM appointments WHERE id = $1', [appointment_id]);
      if (aptResult.rows[0]) {
        await sendSMS(aptResult.rows[0].phone_number, `CSA: Your consultation is complete. Diagnosis: ${diagnosis}. Please follow your doctor's instructions.`);
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
    follow_up_date, status } = req.body;
  try {
    const oldCons = await query('SELECT status, appointment_id FROM consultations WHERE id = $1', [req.params.id]);
    
    const result = await query(`
      UPDATE consultations SET chief_complaint=$1, symptoms=$2, diagnosis=$3, clinical_notes=$4,
        vitals_bp=$5, vitals_temp=$6, vitals_pulse=$7, vitals_weight=$8, vitals_height=$9, vitals_spo2=$10,
        follow_up_date=$11, status=$12
      WHERE id=$13 RETURNING *
    `, [chief_complaint, symptoms, diagnosis, clinical_notes,
      vitals_bp, vitals_temp, vitals_pulse, vitals_weight, vitals_height, vitals_spo2,
      follow_up_date || null, status || 'in_progress', req.params.id]);
    
    if (status === 'completed' && oldCons.rows[0]?.status !== 'completed' && diagnosis) {
      const aptResult = await query('SELECT phone_number FROM appointments WHERE id = $1', [oldCons.rows[0].appointment_id]);
      if (aptResult.rows[0]) {
        await sendSMS(aptResult.rows[0].phone_number, `CSA: Your consultation is complete. Diagnosis: ${diagnosis}. Please follow your doctor's instructions.`);
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
      SELECT lr.*, a.full_name as patient_name, a.appointment_id as apt_code, u.name as doctor_name
      FROM lab_requests lr
      LEFT JOIN appointments a ON lr.appointment_id = a.id
      LEFT JOIN users u ON lr.doctor_id = u.id
    `;
    const conditions: string[] = [];
    const params: any[] = [];
    
    if (patient_id) { conditions.push(`lr.patient_id = $${params.length + 1}`); params.push(patient_id); }
    if (status) { conditions.push(`lr.status = $${params.length + 1}`); params.push(status); }
    
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
    // Get doctor name
    const userResult = await query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    const doctorName = userResult.rows[0]?.name || 'Unknown';
    
    const result = await query(`
      INSERT INTO lab_requests (consultation_id, appointment_id, patient_id, doctor_id, test_name, test_type, urgency, requested_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *
    `, [consultation_id || null, appointment_id, patient_id, req.user.id, test_name, test_type || 'blood', urgency || 'routine', doctorName]);
    res.status(201).json(result.rows[0]);
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
        completed_by=$4, completed_at=${status === 'completed' ? 'CURRENT_TIMESTAMP' : 'completed_at'}
      WHERE id=$5 RETURNING *
    `, [status, results, result_notes, completedBy, req.params.id]);
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
      SELECT sr.*, a.full_name as patient_name, a.appointment_id as apt_code, u.name as doctor_name
      FROM scan_requests sr
      LEFT JOIN appointments a ON sr.appointment_id = a.id
      LEFT JOIN users u ON sr.doctor_id = u.id
    `;
    const conditions: string[] = [];
    const params: any[] = [];
    
    if (patient_id) { conditions.push(`sr.patient_id = $${params.length + 1}`); params.push(patient_id); }
    if (status) { conditions.push(`sr.status = $${params.length + 1}`); params.push(status); }
    
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
    const userResult = await query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    const doctorName = userResult.rows[0]?.name || 'Unknown';
    
    const result = await query(`
      INSERT INTO scan_requests (consultation_id, appointment_id, patient_id, doctor_id, scan_type, body_part, clinical_indication, urgency, requested_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING *
    `, [consultation_id || null, appointment_id, patient_id, req.user.id, scan_type, body_part, clinical_indication, urgency || 'routine', doctorName]);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.put('/api/scans/:id', authenticate, async (req: any, res) => {
  if (!['lab_technician', 'doctor', 'admin'].includes(req.user.role)) {
    return res.status(403).json({ message: 'Forbidden' });
  }
  const { status, results, result_notes } = req.body;
  try {
    const userResult = await query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    const completedBy = userResult.rows[0]?.name || 'Unknown';
    
    const result = await query(`
      UPDATE scan_requests SET status=$1, results=$2, result_notes=$3,
        completed_by=$4, completed_at=${status === 'completed' ? 'CURRENT_TIMESTAMP' : 'completed_at'}
      WHERE id=$5 RETURNING *
    `, [status, results, result_notes, completedBy, req.params.id]);
    res.json(result.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

// --- Patient History (Aggregated Timeline) ---
app.get('/api/patients/:id/history', authenticate, async (req: any, res) => {
  const patientId = req.params.id;
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
app.get('/api/doctors', async (req, res) => {
  try {
    const result = await query('SELECT * FROM doctors ORDER BY name');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/doctors', async (req, res) => {
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

app.put('/api/doctors/:id', async (req, res) => {
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

app.patch('/api/doctors/:id/status', async (req, res) => {
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
app.get('/api/analytics/dashboard', authenticate, async (req: any, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];
    let doctorId = null;

    if (req.user.role === 'doctor') {
      const docResult = await query('SELECT id FROM doctors WHERE user_id = $1', [req.user.id]);
      if (docResult.rows.length > 0) {
        doctorId = docResult.rows[0].id;
      } else {
        return res.status(403).json({ message: 'Doctor record not found' });
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

const TELEMED_COPAY_GHS = 50;
const TELEMED_COPAY_PESewas = TELEMED_COPAY_GHS * 100;

function generateMeetingLink() {
  const chars = 'abcdefghijklmnopqrstuvwxyz';
  const getChars = (len: number) => Array.from({ length: len }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
  return `https://meet.jit.si/graprime-telemed-${getChars(3)}-${getChars(4)}-${getChars(3)}`;
}

async function finalizeAppointmentPayment(appointmentId: number, paymentRef: string, patientUserId?: number) {
  const aptResult = await query('SELECT * FROM appointments WHERE id = $1', [appointmentId]);
  const apt = aptResult.rows[0];
  if (!apt) return null;

  let meetingLink = apt.meeting_link;
  if (apt.is_telemedicine && !meetingLink) {
    meetingLink = generateMeetingLink();
  }

  await query(`
    UPDATE appointments
    SET payment_status = $1,
        payment_ref = $2,
        meeting_link = $3,
        status = 'approved'
    WHERE id = $4
  `, ['paid', paymentRef, meetingLink, appointmentId]);

  if (apt.is_telemedicine && meetingLink && apt.phone_number) {
    const scheduledInfo = `${new Date(apt.preferred_date).toLocaleDateString()} at ${apt.preferred_time}`;
    await sendSMS(
      apt.phone_number,
      `CSA: Payment Confirmed! Your session for ${scheduledInfo} is set. Join here: ${meetingLink}`
    ).catch(e => console.error('SMS Error after payment:', e));
  }

  if (patientUserId && apt.doctor_id) {
    const docResult = await query('SELECT user_id FROM doctors WHERE id = $1', [apt.doctor_id]);
    const doctorUserId = docResult.rows[0]?.user_id;
    if (doctorUserId) {
      await query(`
        INSERT INTO chat_threads (patient_user_id, doctor_user_id)
        VALUES ($1, $2)
        ON CONFLICT (patient_user_id, doctor_user_id) DO NOTHING
      `, [patientUserId, doctorUserId]);
    }
  }

  return { meetingLink, paymentRef };
}

app.post('/api/appointments/:id/pay/initialize', authenticate, async (req: any, res) => {
  const { id } = req.params;
  try {
    const aptResult = await query('SELECT * FROM appointments WHERE id = $1', [id]);
    const apt = aptResult.rows[0];
    if (!apt) return res.status(404).json({ message: 'Appointment not found' });

    const paystackKey = process.env.PAYSTACK_SECRET_KEY;
    if (!paystackKey) {
      return res.json({ mock: true });
    }

    const userResult = await query('SELECT * FROM users WHERE id = $1', [req.user.id]);
    const user = userResult.rows[0];
    const email = user?.username?.includes('@')
      ? user.username
      : `patient${String(user?.phone_number || user?.id).replace(/\D/g, '')}@digihealth.app`;

    const reference = `DH-${id}-${Date.now()}`;
    const callbackUrl = process.env.PAYSTACK_CALLBACK_URL || 'https://standard.paystack.co/close';

    const paystackRes = await axios.post(
      'https://api.paystack.co/transaction/initialize',
      {
        email,
        amount: TELEMED_COPAY_PESewas,
        currency: 'GHS',
        reference,
        callback_url: callbackUrl,
        metadata: {
          appointment_id: id,
          user_id: req.user.id,
        },
      },
      {
        headers: {
          Authorization: `Bearer ${paystackKey}`,
          'Content-Type': 'application/json',
        },
      }
    );

    const data = paystackRes.data?.data;
    await query(`
      INSERT INTO payments (appointment_id, amount, currency, status, reference, gateway)
      VALUES ($1, $2, 'GHS', 'pending', $3, 'paystack')
      ON CONFLICT (reference) DO NOTHING
    `, [id, TELEMED_COPAY_GHS, reference]);

    res.json({
      authorization_url: data.authorization_url,
      reference: data.reference,
      amount: TELEMED_COPAY_GHS,
    });
  } catch (err: any) {
    console.error('Paystack initialize error:', err.response?.data || err.message);
    res.status(500).json({ message: 'Payment initialization failed' });
  }
});

app.post('/api/appointments/:id/pay/verify', authenticate, async (req: any, res) => {
  const { id } = req.params;
  const { reference } = req.body;
  try {
    const paystackKey = process.env.PAYSTACK_SECRET_KEY;
    if (!paystackKey) {
      const result = await finalizeAppointmentPayment(Number(id), `MOCK-${Date.now()}`, req.user.id);
      return res.json({ message: 'Payment successful', ...result });
    }

    const verifyRes = await axios.get(
      `https://api.paystack.co/transaction/verify/${reference}`,
      { headers: { Authorization: `Bearer ${paystackKey}` } }
    );

    const status = verifyRes.data?.data?.status;
    if (status !== 'success') {
      return res.status(400).json({ message: 'Payment not completed' });
    }

    await query(
      `UPDATE payments SET status = 'paid' WHERE reference = $1`,
      [reference]
    );

    const result = await finalizeAppointmentPayment(Number(id), reference, req.user.id);
    res.json({ message: 'Payment successful', ...result });
  } catch (err: any) {
    console.error('Paystack verify error:', err.response?.data || err.message);
    res.status(500).json({ message: 'Payment verification failed' });
  }
});

// --- Secure Chat ---
app.get('/api/chat/threads', authenticate, async (req: any, res) => {
  try {
    const userId = req.user.id;
    const role = req.user.role;
    let result;

    if (role === 'patient') {
      result = await query(`
        SELECT t.*,
               u.name AS other_name,
               (
                 SELECT body FROM chat_messages m
                 WHERE m.thread_id = t.id
                 ORDER BY m.created_at DESC LIMIT 1
               ) AS last_message,
               (
                 SELECT COUNT(*)::int FROM chat_messages m
                 WHERE m.thread_id = t.id AND m.is_read = FALSE AND m.sender_user_id != $1
               ) AS unread_count
        FROM chat_threads t
        JOIN users u ON u.id = t.doctor_user_id
        WHERE t.patient_user_id = $1
        ORDER BY t.last_message_at DESC
      `, [userId]);
    } else if (role === 'doctor') {
      result = await query(`
        SELECT t.*,
               u.name AS other_name,
               (
                 SELECT body FROM chat_messages m
                 WHERE m.thread_id = t.id
                 ORDER BY m.created_at DESC LIMIT 1
               ) AS last_message,
               (
                 SELECT COUNT(*)::int FROM chat_messages m
                 WHERE m.thread_id = t.id AND m.is_read = FALSE AND m.sender_user_id != $1
               ) AS unread_count
        FROM chat_threads t
        JOIN users u ON u.id = t.patient_user_id
        WHERE t.doctor_user_id = $1
        ORDER BY t.last_message_at DESC
      `, [userId]);
    } else {
      return res.status(403).json({ message: 'Forbidden' });
    }

    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/chat/threads', authenticate, async (req: any, res) => {
  try {
    if (req.user.role !== 'patient') {
      return res.status(403).json({ message: 'Only patients can start threads' });
    }

    let { doctorUserId, doctorId } = req.body;
    if (!doctorUserId && doctorId) {
      const doc = await query('SELECT user_id FROM doctors WHERE id = $1', [doctorId]);
      doctorUserId = doc.rows[0]?.user_id;
    }
    if (!doctorUserId) {
      return res.status(400).json({ message: 'doctorUserId or doctorId required' });
    }

    const existing = await query(
      'SELECT * FROM chat_threads WHERE patient_user_id = $1 AND doctor_user_id = $2',
      [req.user.id, doctorUserId]
    );
    if (existing.rows[0]) {
      const row = existing.rows[0];
      const doctor = await query('SELECT name FROM users WHERE id = $1', [doctorUserId]);
      return res.json({ ...row, other_name: doctor.rows[0]?.name || 'Doctor' });
    }

    const created = await query(`
      INSERT INTO chat_threads (patient_user_id, doctor_user_id)
      VALUES ($1, $2)
      RETURNING *
    `, [req.user.id, doctorUserId]);

    const doctor = await query('SELECT name FROM users WHERE id = $1', [doctorUserId]);
    res.status(201).json({ ...created.rows[0], other_name: doctor.rows[0]?.name || 'Doctor' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/chat/threads/:threadId/messages', authenticate, async (req: any, res) => {
  const { threadId } = req.params;
  try {
    const thread = await query('SELECT * FROM chat_threads WHERE id = $1', [threadId]);
    const t = thread.rows[0];
    if (!t) return res.status(404).json({ message: 'Thread not found' });

    const userId = req.user.id;
    if (userId !== t.patient_user_id && userId !== t.doctor_user_id) {
      return res.status(403).json({ message: 'Forbidden' });
    }

    await query(
      'UPDATE chat_messages SET is_read = TRUE WHERE thread_id = $1 AND sender_user_id != $2',
      [threadId, userId]
    );

    const messages = await query(
      'SELECT * FROM chat_messages WHERE thread_id = $1 ORDER BY created_at ASC',
      [threadId]
    );
    res.json(messages.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/chat/threads/:threadId/messages', authenticate, async (req: any, res) => {
  const { threadId } = req.params;
  const { body } = req.body;
  try {
    if (!body || !String(body).trim()) {
      return res.status(400).json({ message: 'Message body required' });
    }

    const thread = await query('SELECT * FROM chat_threads WHERE id = $1', [threadId]);
    const t = thread.rows[0];
    if (!t) return res.status(404).json({ message: 'Thread not found' });

    const userId = req.user.id;
    if (userId !== t.patient_user_id && userId !== t.doctor_user_id) {
      return res.status(403).json({ message: 'Forbidden' });
    }

    const inserted = await query(`
      INSERT INTO chat_messages (thread_id, sender_user_id, body)
      VALUES ($1, $2, $3)
      RETURNING *
    `, [threadId, userId, String(body).trim()]);

    await query(
      'UPDATE chat_threads SET last_message_at = CURRENT_TIMESTAMP WHERE id = $1',
      [threadId]
    );

    res.status(201).json(inserted.rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.listen(Number(PORT), '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
});
