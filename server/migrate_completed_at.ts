import pg from 'pg';
import dotenv from 'dotenv';
import path from 'path';
const { Pool } = pg;

dotenv.config({ path: path.join(process.cwd(), '../.env') });

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function migrate() {
  try {
    await pool.query('ALTER TABLE appointments ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP');
    console.log('Added completed_at column to appointments.');
    await pool.end();
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}

migrate();
