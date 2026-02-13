const mysql = require('mysql2/promise');
require('dotenv').config({ path: '../.env' });

async function run() {
    let connection;
    try {
        connection = await mysql.createConnection({
            host: process.env.DB_HOST || 'localhost',
            user: process.env.DB_USER || 'root',
            password: process.env.DB_PASSWORD || '',
            database: process.env.DB_NAME || 'servenow',
            port: process.env.DB_PORT || 3306
        });

        console.log('Starting data cleanup...');

        // 1. Clear Transactional Data (Orders)
        // Note: order_items has a FK to orders, so we must delete from order_items first?
        // Actually, if ON DELETE CASCADE is set, deleting orders is enough.
        // But to be safe and explicit:
        console.log('Deleting order_items...');
        await connection.execute('DELETE FROM order_items');
        
        console.log('Deleting orders...');
        await connection.execute('DELETE FROM orders');

        // 2. Clear Financial Data
        // Based on typical schema: payments, wallets, transactions
        console.log('Deleting payments...');
        await connection.execute('DELETE FROM payments');

        console.log('Deleting wallet_transactions...');
        await connection.execute('DELETE FROM wallet_transactions');

        // Note: Do we want to reset wallet balances to 0 or delete the wallets entirely?
        // User asked to "keep users", and wallets are usually 1:1 with users.
        // It's safer to RESET balances to 0.00 rather than delete the rows, 
        // because the application might expect a wallet row to exist for a user.
        console.log('Resetting wallet balances...');
        await connection.execute('UPDATE wallets SET balance = 0.00');

        console.log('Cleanup complete. Users, Products, Stores, and Categories are preserved.');

    } catch (e) {
        console.error('Error during cleanup:', e);
    } finally {
        if (connection) await connection.end();
    }
}

run();
