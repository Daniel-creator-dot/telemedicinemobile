import pg from 'pg';
import dotenv from 'dotenv';
import bcrypt from 'bcryptjs';

dotenv.config({ path: 'C:\\Users\\inspy\\OneDrive\\Documents\\graprime\\graprime\\.env' });

const { Client } = pg;

const client = new Client({
  connectionString: process.env.DATABASE_URL,
});

async function main() {
  try {
    await client.connect();
    const res = await client.query('SELECT username, password, role FROM users');
    
    console.log('Testing passwords for found users...');
    const passwordsToTest = ['admin', 'admin123', 'staff123', 'labtech123', 'password123', 'daniel', 'password'];
    
    for (const row of res.rows) {
      console.log(`\nUser: ${row.username} (Role: ${row.role})`);
      let matched = false;
      for (const pass of passwordsToTest) {
        const isMatch = await bcrypt.compare(pass, row.password);
        if (isMatch) {
          console.log(`  -> MATCHED PASSWORD: "${pass}"`);
          matched = true;
          break;
        }
      }
      if (!matched) {
        console.log(`  -> Hash is: ${row.password} (none of the standard passwords matched)`);
      }
    }
  } catch (err) {
    console.error('Error:', err);
  } finally {
    await client.end();
  }
}

main();
