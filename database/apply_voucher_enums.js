const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
const path = require('path');

dotenv.config({ path: path.join(__dirname, '../.env') });

async function applyChanges() {
    let connection;
    try {
        console.log('Connecting to database...');
        connection = await mysql.createConnection({
            host: process.env.DB_HOST,
            user: process.env.DB_USER,
            password: process.env.DB_PASSWORD,
            database: process.env.DB_NAME,
            port: process.env.DB_PORT
        });
        console.log('Connected.');

        // Update cash_payment_vouchers payee_type
        try {
            await connection.execute(`
                ALTER TABLE cash_payment_vouchers 
                MODIFY COLUMN payee_type ENUM('store', 'rider', 'vendor', 'employee', 'expense', 'other') NOT NULL
            `);
            console.log('Updated cash_payment_vouchers payee_type enum.');
        } catch (err) {
            console.error('Error updating cash_payment_vouchers:', err.message);
        }

        // Update cash_receipt_vouchers payer_type
        try {
            await connection.execute(`
                ALTER TABLE cash_receipt_vouchers 
                MODIFY COLUMN payer_type ENUM('customer', 'store', 'rider', 'vendor', 'employee', 'expense', 'other') NOT NULL
            `);
            console.log('Updated cash_receipt_vouchers payer_type enum.');
        } catch (err) {
            console.error('Error updating cash_receipt_vouchers:', err.message);
        }

    } catch (error) {
        console.error('Error:', error);
    } finally {
        if (connection) await connection.end();
    }
}

applyChanges();
