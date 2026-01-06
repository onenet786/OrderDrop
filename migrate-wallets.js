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
        await connection.query('ALTER TABLE wallets MODIFY user_id INT NULL');
        await connection.query('ALTER TABLE wallets ADD COLUMN rider_id INT UNIQUE NULL AFTER user_id');
        await connection.query('ALTER TABLE wallets ADD CONSTRAINT fk_wallets_rider FOREIGN KEY (rider_id) REFERENCES riders(id) ON DELETE CASCADE');
        console.log('Migration successful');
    } catch (e) {
        console.error('Migration failed:', e);
    } finally {
        if (connection) await connection.end();
    }
}
migrate();
