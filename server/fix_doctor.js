const pg = require('pg');
const dotenv = require('dotenv');

dotenv.config();

const { Client } = pg;

const client = new Client({
  connectionString: process.env.DATABASE_URL,
});

async function main() {
  try {
    await client.connect();
    console.log('Connected to database');

    // Check if doctor1 user exists
    const userResult = await client.query('SELECT id, username, name FROM users WHERE username = $1', ['doctor1']);
    
    if (userResult.rows.length === 0) {
      console.log('User doctor1 not found');
      process.exit(1);
    }

    const user = userResult.rows[0];
    console.log('Found user:', user);

    // Check if doctor record already exists
    const doctorResult = await client.query('SELECT id FROM doctors WHERE user_id = $1', [user.id]);
    
    if (doctorResult.rows.length > 0) {
      console.log('Doctor record already exists for this user');
      process.exit(0);
    }

    // Create doctor record
    const insertResult = await client.query(
      'INSERT INTO doctors (user_id, name, specialization) VALUES ($1, $2, $3) RETURNING *',
      [user.id, user.name, 'General Physician']
    );

    console.log('Doctor record created successfully:');
    console.table(insertResult.rows);

  } catch (err) {
    console.error('Error:', err);
  } finally {
    await client.end();
  }
}

main();
