import pg from 'pg';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: 'C:\\Users\\inspy\\OneDrive\\Documents\\graprime\\graprime\\.env' });

const { Client } = pg;

const client = new Client({
  connectionString: process.env.DATABASE_URL,
});

async function main() {
  try {
    await client.connect();
    const res = await client.query('SELECT id, username, role, name FROM users');
    console.log('--- REGISTERED USERS ---');
    console.table(res.rows);
  } catch (err) {
    console.error('Error querying database:', err);
  } finally {
    await client.end();
  }
}

main();
