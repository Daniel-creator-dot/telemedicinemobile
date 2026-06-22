import bcrypt from 'bcryptjs';
import { query, initDb } from './db.js';

const seed = async () => {
  try {
    // Initialize DB tables first
    await initDb();

    console.log('Cleaning existing data...');
    await query('TRUNCATE appointments, patients, doctors, notifications, users CASCADE');

    console.log('Seeding users...');
    const adminPassword = await bcrypt.hash('admin123', 10);
    const staffPassword = await bcrypt.hash('staff123', 10);

    // Create Admin
    await query(`
      INSERT INTO users (username, password, role, name) 
      VALUES ($1, $2, $3, $4)
    `, ['admin', adminPassword, 'admin', 'System Administrator']);

    // Create Doctors as Users
    const doctorUsers = await query(`
      INSERT INTO users (username, password, role, name)
      VALUES 
        ('dr_appiah', $1, 'doctor', 'Dr. Kwesi Appiah'),
        ('dr_mensah', $1, 'doctor', 'Dr. Sarah Mensah'),
        ('dr_doe', $1, 'doctor', 'Dr. John Doe'),
        ('frontdesk1', $1, 'front_desk', 'Janet Mensah')
      RETURNING id, name, role
    `, [staffPassword]);

    console.log('Seeding doctor profiles...');
    const doctorProfiles = [
      ['Dr. Kwesi Appiah', 'General Physician', 15, '08:00', '17:00'],
      ['Dr. Sarah Mensah', 'Pediatrician', 30, '09:00', '16:00'],
      ['Dr. John Doe', 'Cardiologist', 20, '08:30', '17:30']
    ];

    const docIds: number[] = [];
    for (let i = 0; i < 3; i++) {
      const user = doctorUsers.rows[i];
      const profile = doctorProfiles[i];
      const res = await query(`
        INSERT INTO doctors (user_id, name, specialization, slot_duration, start_time, end_time)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id
      `, [user.id, profile[0], profile[1], profile[2], profile[3], profile[4]]);
      docIds.push(res.rows[0].id);
    }

    console.log('Seeding patients...');
    const patientResult = await query(`
      INSERT INTO patients (staff_id, full_name, email, phone_number, department)
      VALUES 
        ('STAFF001', 'Alice Johnson', 'alice@example.com', '0244111222', 'Marketing'),
        ('STAFF002', 'Bob Smith', 'bob@example.com', '0244333444', 'Engineering')
      RETURNING id
    `);
    const patIds = patientResult.rows.map(r => r.id);

    console.log('Seeding appointments...');
    const today = new Date().toISOString().split('T')[0];
    await query(`
      INSERT INTO appointments (appointment_id, patient_id, full_name, email, phone_number, staff_id, department, doctor_id, preferred_date, preferred_time, status, priority)
      VALUES 
        ('APT-1001', $1, 'Alice Johnson', 'alice@example.com', '0244111222', 'STAFF001', 'Marketing', $3, $5, '09:00', 'approved', 'High'),
        ('APT-1002', $2, 'Bob Smith', 'bob@example.com', '0244333444', 'STAFF002', 'Engineering', $4, $5, '10:30', 'pending', 'Medium')
    `, [patIds[0], patIds[1], docIds[0], docIds[1], today]);

    console.log('Seeding notifications...');
    await query('INSERT INTO notifications (message) VALUES ($1)', ['Welcome to CSA HEALTH Admin Portal!']);

    console.log('Seeding completed successfully');
    process.exit(0);
  } catch (err) {
    console.error('Error seeding database:', err);
    process.exit(1);
  }
};

seed();
