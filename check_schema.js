const mysql = require('mysql2/promise');
require('dotenv').config();

async function checkSchema() {
    let connection;
    try {
        connection = await mysql.createConnection({
            host: process.env.DB_HOST || 'localhost',
            user: process.env.DB_USER || 'root',
            password: process.env.DB_PASSWORD || '',
            database: process.env.DB_NAME || 'servenow'
        });

        console.log('Connected to database');
        
        const [rows] = await connection.execute("SHOW COLUMNS FROM financial_reports LIKE 'report_type'");
        console.log('Column definition:', rows[0].Type);

    } catch (error) {
        console.error('Error:', error);
    } finally {
        if (connection) {
            await connection.end();
        }
    }
}

checkSchema();
