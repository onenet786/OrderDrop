const mysql = require('mysql2/promise');
require('dotenv').config();

async function updateSchema() {
    let connection;
    try {
        connection = await mysql.createConnection({
            host: process.env.DB_HOST,
            user: process.env.DB_USER,
            password: process.env.DB_PASSWORD,
            database: process.env.DB_NAME
        });

        console.log('Connected to database');

        // Check if store_id exists in wallets
        const [columns] = await connection.execute('SHOW COLUMNS FROM wallets LIKE "store_id"');
        
        if (columns.length === 0) {
            console.log('Adding store_id to wallets table...');
            await connection.execute('ALTER TABLE wallets ADD COLUMN store_id INT UNIQUE AFTER user_id');
            await connection.execute('ALTER TABLE wallets ADD FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE');
            await connection.execute('ALTER TABLE wallets ADD INDEX idx_wallets_store_id (store_id)');
            console.log('store_id added successfully.');
        } else {
            console.log('store_id already exists in wallets table.');
        }

    } catch (error) {
        console.error('Error updating schema:', error);
    } finally {
        if (connection) {
            await connection.end();
        }
    }
}

updateSchema();
