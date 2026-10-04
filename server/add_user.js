const pg = require('pg');
const dotenv = require('dotenv');
const bcrypt = require('bcryptjs');

dotenv.config();

const { Client } = pg;

const client = new Client({
  connectionString: process.env.DATABASE_URL,
});

async function main() {
  // Get command line arguments
  const args = process.argv.slice(2);
  
  if (args.length < 4) {
    console.log('Usage: node add_user.js <username> <password> <name> <role> [phone] [email]');
    console.log('Example: node add_user.js john pass123 "John Doe" patient "+1234567890" "john@example.com"');
    console.log('Roles: admin, doctor, staff, patient');
    process.exit(1);
  }

  const [username, password, name, role, phone, email] = args;

  try {
    await client.connect();
    console.log('Connected to database');

    // Check if user already exists
    const existingUser = await client.query('SELECT id FROM users WHERE username = $1', [username]);
    if (existingUser.rows.length > 0) {
      console.log('Error: Username already exists');
      process.exit(1);
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);

    // Insert user
    const result = await client.query(
      'INSERT INTO users (username, password, role, name, phone_number) VALUES ($1, $2, $3, $4, $5) RETURNING id, username, role, name',
      [username, hashedPassword, role, name, phone || null]
    );

    console.log('\nUser created successfully:');
    console.table(result.rows);

    // If role is patient, also create patient record
    if (role === 'patient') {
      await client.query(
        'INSERT INTO patients (full_name, email, phone_number) VALUES ($1, $2, $3)',
        [name, email || null, phone || null]
      );
      console.log('Patient record also created');
    }

  } catch (err) {
    console.error('Error:', err);
  } finally {
    await client.end();
  }
}

main();
