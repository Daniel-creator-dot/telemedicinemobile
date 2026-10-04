import { query } from './db';

export async function getPatientForUser(userId: number) {
  const byUser = await query('SELECT * FROM patients WHERE user_id = $1', [userId]);
  if (byUser.rows[0]) return byUser.rows[0];

  const user = await query('SELECT * FROM users WHERE id = $1', [userId]);
  const phone = user.rows[0]?.phone_number;
  if (!phone) return null;

  const byPhone = await query('SELECT * FROM patients WHERE phone_number = $1 ORDER BY id DESC LIMIT 1', [phone]);
  if (byPhone.rows[0]) {
    await query('UPDATE patients SET user_id = $1 WHERE id = $2 AND user_id IS NULL', [userId, byPhone.rows[0].id]);
    return { ...byPhone.rows[0], user_id: userId };
  }
  return null;
}

export async function resolvePatientIdFromAppointment(
  appointmentId?: number | null,
  fallback?: number | null
) {
  if (fallback) return Number(fallback);
  if (!appointmentId) return null;
  const row = await query('SELECT patient_id FROM appointments WHERE id = $1', [appointmentId]);
  return row.rows[0]?.patient_id ? Number(row.rows[0].patient_id) : null;
}

export async function getAccessiblePatientIds(userId: number): Promise<number[]> {
  const patient = await getPatientForUser(userId);
  if (!patient) return [];
  const deps = await query(
    'SELECT dependent_patient_id FROM dependents WHERE guardian_patient_id = $1',
    [patient.id]
  );
  return [Number(patient.id), ...deps.rows.map((r: { dependent_patient_id: number }) => Number(r.dependent_patient_id))];
}
