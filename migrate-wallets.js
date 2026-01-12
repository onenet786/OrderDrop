const mysql = require('mysql2/promise');
require('dotenv').config();

async function migrate() {
    let connection;
    try {
        connection = await mysql.createConnection({
            host: process.env.DB_HOST || 'localhost',
            user: process.env.DB_USER || 'root',
            password: process.env.DB_PASSWORD || '',
            port: process.env.DB_PORT || 3306,
            database: process.env.DB_NAME || 'servenow'
        });

        console.log('Running migration...');
        
        // Check if rider_id column exists
        const [columns] = await connection.query(
            'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = "wallets" AND COLUMN_NAME = "rider_id"'
        );
        
        if (columns.length === 0) {
            await connection.query('ALTER TABLE wallets MODIFY user_id INT NULL');
            await connection.query('ALTER TABLE wallets ADD COLUMN rider_id INT UNIQUE NULL AFTER user_id');
            await connection.query('ALTER TABLE wallets ADD CONSTRAINT fk_wallets_rider FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE');
        }
        
        // Check if user_type column exists
        const [typeColumns] = await connection.query(
            'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = "wallets" AND COLUMN_NAME = "user_type"'
        );
        
        if (typeColumns.length === 0) {
            await connection.query('ALTER TABLE wallets ADD COLUMN user_type ENUM("customer", "rider") DEFAULT "customer" AFTER rider_id');
        }
        
        // Add index on rider_id if it doesn't exist
        const [indices] = await connection.query(
            'SELECT INDEX_NAME FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_NAME = "wallets" AND COLUMN_NAME = "rider_id"'
        );
        
        if (indices.length === 0) {
            await connection.query('CREATE INDEX idx_wallets_rider_id ON wallets(rider_id)');
        }
        
        console.log('Migration successful');
    } catch (e) {
        console.error('Migration failed:', e);
    } finally {
        if (connection) await connection.end();
    }
}
migrate();
