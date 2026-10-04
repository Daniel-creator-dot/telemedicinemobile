import { query } from './db';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.join(process.cwd(), '../.env') });

async function test() {
  try {
    const res = await query('SELECT * FROM appointments WHERE id = 7');
    console.log('APPOINTMENT:', res.rows[0]);
    process.exit(0);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}
test();
