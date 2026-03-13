const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
const path = require('path');

dotenv.config();

async function run() {
    const connection = await mysql.createConnection({
        host: process.env.DB_HOST,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME,
        port: process.env.DB_PORT || 3306
    });

    async function columnExists(table, column) {
        const [rows] = await connection.execute(
            'SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            [process.env.DB_NAME, table, column]
        );
        return rows[0].cnt > 0;
    }

    try {
        if (!await columnExists('users', 'reset_password_token')) {
            console.log('Adding reset_password_token to users...');
            await connection.execute('ALTER TABLE users ADD COLUMN reset_password_token VARCHAR(255) DEFAULT NULL');
        }
        if (!await columnExists('users', 'reset_password_expires')) {
            console.log('Adding reset_password_expires to users...');
            await connection.execute('ALTER TABLE users ADD COLUMN reset_password_expires DATETIME DEFAULT NULL');
        }
        
        if (!await columnExists('riders', 'reset_password_token')) {
            console.log('Adding reset_password_token to riders...');
            await connection.execute('ALTER TABLE riders ADD COLUMN reset_password_token VARCHAR(255) DEFAULT NULL');
        }
        if (!await columnExists('riders', 'reset_password_expires')) {
            console.log('Adding reset_password_expires to riders...');
            await connection.execute('ALTER TABLE riders ADD COLUMN reset_password_expires DATETIME DEFAULT NULL');
        }
        
        console.log('Migration successful!');
    } catch (error) {
        console.error('Migration failed:', error);
    } finally {
        await connection.end();
    }
}

run();
