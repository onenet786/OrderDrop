const mysql = require('mysql2/promise');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function migrateDatabase() {
    let connection;

    try {
        console.log('Connecting to MySQL...');

        connection = await mysql.createConnection({
            host: process.env.DB_HOST,
            user: process.env.DB_USER,
            password: process.env.DB_PASSWORD,
            port: process.env.DB_PORT,
            database: process.env.DB_NAME
        });

        console.log('Connected to database:', process.env.DB_NAME);

        // Check if priority column already exists
        const [columns] = await connection.query(
            "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'stores' AND COLUMN_NAME = 'priority'"
        );

        if (columns.length > 0) {
            console.log('✓ Priority column already exists in stores table');
            await connection.end();
            return;
        }

        console.log('Adding priority column to stores table...');

        // Add priority column with unique constraint
        await connection.query(
            'ALTER TABLE stores ADD COLUMN priority INT DEFAULT NULL'
        );
        console.log('✓ Priority column added');

        // Add unique constraint
        await connection.query(
            'ALTER TABLE stores ADD UNIQUE KEY unique_priority (priority)'
        );
        console.log('✓ Unique constraint added');

        console.log('\n✓ Migration completed successfully!');
        console.log('The priority system is now ready to use.');

    } catch (error) {
        console.error('Migration failed:', error.message);
        process.exit(1);
    } finally {
        if (connection) {
            await connection.end();
        }
    }
}

migrateDatabase();
