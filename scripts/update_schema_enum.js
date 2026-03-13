const mysql = require('mysql2/promise');
require('dotenv').config();

async function updateEnum() {
    let connection;
    try {
        connection = await mysql.createConnection({
            host: process.env.DB_HOST,
            user: process.env.DB_USER,
            password: process.env.DB_PASSWORD,
            database: process.env.DB_NAME
        });

        console.log('Connected to database');
        
        console.log('Updating user_type ENUM in wallets table...');
        await connection.execute("ALTER TABLE wallets MODIFY COLUMN user_type ENUM('customer', 'rider', 'store', 'admin', 'employee') DEFAULT 'customer'");
        console.log('ENUM updated successfully.');

    } catch (error) {
        console.error('Error updating schema:', error);
    } finally {
        if (connection) {
            await connection.end();
        }
    }
}

updateEnum();
