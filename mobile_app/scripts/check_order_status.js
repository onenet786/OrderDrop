const mysql = require('mysql2/promise');
require('dotenv').config({ path: '../.env' });

async function checkOrderStatus() {
    let connection;
    try {
        connection = await mysql.createConnection({
            host: process.env.DB_HOST || 'localhost',
            user: process.env.DB_USER || 'root',
            password: process.env.DB_PASSWORD || '',
            database: process.env.DB_NAME || 'servenow',
            port: process.env.DB_PORT || 3306
        });

        const orderNumber = 'Ord2602140001';
        console.log(`Checking status for order: ${orderNumber}`);

        // 1. Get Order Details
        const [orders] = await connection.execute(
            'SELECT id, order_number, status, created_at FROM orders WHERE order_number = ?',
            [orderNumber]
        );

        if (orders.length === 0) {
            console.log('Order not found.');
            return;
        }

        const order = orders[0];
        console.log('Global Order Status:', order);

        // 2. Get Item Details (Store Status)
        const [items] = await connection.execute(
            `SELECT oi.id, oi.product_id, oi.quantity, oi.item_status, s.name as store_name, s.id as store_id
             FROM order_items oi
             JOIN stores s ON oi.store_id = s.id
             WHERE oi.order_id = ?`,
            [order.id]
        );

        console.log('\nOrder Items (Store Level Status):');
        console.table(items.map(i => ({
            item_id: i.id,
            store: i.store_name,
            store_id: i.store_id,
            status: i.item_status || 'NULL (defaults to pending)'
        })));

    } catch (e) {
        console.error('Error:', e);
    } finally {
        if (connection) await connection.end();
    }
}

checkOrderStatus();
