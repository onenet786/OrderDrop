const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
require('dotenv').config();

async function resetPassword() {
    const connection = await mysql.createConnection({
        host: process.env.DB_HOST,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME
    });

    const email = 'owner@servenow.pk';
    const newPassword = '123456';
    
    // Hash the password
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    
    // Update user
    const [result] = await connection.execute(
        'UPDATE users SET password = ?, is_verified = 1, is_active = 1 WHERE email = ?',
        [hashedPassword, email]
    );

    if (result.affectedRows > 0) {
        console.log(`Password for ${email} has been reset to: ${newPassword}`);
        console.log('User marked as verified and active.');
    } else {
        console.log(`User ${email} not found!`);
        
        // Create if missing
        console.log('Creating user...');
        await connection.execute(
            'INSERT INTO users (first_name, last_name, email, password, phone, user_type, is_verified, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            ['Store', 'Owner', email, hashedPassword, '03001234567', 'store_owner', 1, 1]
        );
        console.log('User created.');
    }

    await connection.end();
}

resetPassword().catch(console.error);
