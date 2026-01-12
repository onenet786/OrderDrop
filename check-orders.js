const mysql = require('mysql2/promise');
require('dotenv').config();

async function check() {
    let connection;
    try {
        connection = await mysql.createConnection({
            host: process.env.DB_HOST || 'localhost',
            user: process.env.DB_USER || 'root',
            password: process.env.DB_PASSWORD || '',
            port: process.env.DB_PORT || 3306,
            database: process.env.DB_NAME || 'servenow'
        });

        const email = 'aaqueel@servenow.com';

        // Check if rider exists
        const [riderByEmail] = await connection.query(`
            SELECT id, email, first_name, last_name FROM riders WHERE email = ?
        `, [email]);
        
        console.log('Rider with email aaqueel@servenow.com:', riderByEmail);

        // Check orders for any rider with this email
        if (riderByEmail.length > 0) {
            const riderId = riderByEmail[0].id;
            
            // Check orders for this rider
            const [orders] = await connection.query(`
                SELECT id, user_id, store_id, rider_id, total_amount, delivery_fee, payment_method, payment_status, status, created_at
                FROM orders WHERE rider_id = ?
            `, [riderId]);
            
            console.log(`\nOrders for rider ID ${riderId}:`, orders.length > 0 ? orders : 'No orders');
        }

    } catch (e) {
        console.error('Error:', e.message);
    } finally {
        if (connection) await connection.end();
    }
}
check();
