const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
require('dotenv').config();

const dbConfig = {
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'servenow'
};

(async () => {
    try {
        const conn = await mysql.createConnection(dbConfig);
        
        console.log('--- Fixing Data ---');

        // 1. Create/Update Store Owner
        const email = 'owner@servenow.pk';
        const password = await bcrypt.hash('123456', 10);
        
        let [users] = await conn.execute('SELECT id FROM users WHERE email = ?', [email]);
        let ownerId;
        
        if (users.length === 0) {
            console.log('Creating store owner...');
            const [res] = await conn.execute(
                'INSERT INTO users (first_name, last_name, email, password, user_type, phone) VALUES (?, ?, ?, ?, ?, ?)',
                ['Store', 'Owner', email, password, 'store_owner', '03001234567']
            );
            ownerId = res.insertId;
        } else {
            console.log('Store owner exists.');
            ownerId = users[0].id;
            // Ensure type is store_owner
            await conn.execute('UPDATE users SET user_type = "store_owner" WHERE id = ?', [ownerId]);
        }
        console.log('Owner ID:', ownerId);

        // 2. Assign Store to Owner
        const storeName = 'King Burger'; // Using an existing store name from previous output
        let [stores] = await conn.execute('SELECT id FROM stores WHERE name = ?', [storeName]);
        let storeId;
        
        if (stores.length === 0) {
             console.log('Creating store...');
             const [res] = await conn.execute(
                 'INSERT INTO stores (name, owner_id, address, phone, image_url) VALUES (?, ?, ?, ?, ?)',
                 [storeName, ownerId, '123 Burger St', '03001111111', 'burgers.jpg']
             );
             storeId = res.insertId;
        } else {
            console.log('Store exists. Updating owner...');
            storeId = stores[0].id;
            await conn.execute('UPDATE stores SET owner_id = ? WHERE id = ?', [ownerId, storeId]);
        }
        console.log('Store ID:', storeId);

        // 3. Create/Update Rider
        const riderEmail = 'faizan@servenow.pk';
        const riderName = 'Faizan';
        const riderLastName = 'Aziz';
        
        let [riders] = await conn.execute('SELECT id FROM riders WHERE email = ?', [riderEmail]);
        let riderId;
        
        if (riders.length === 0) {
             console.log('Creating rider...');
             const [res] = await conn.execute(
                 'INSERT INTO riders (first_name, last_name, email, phone, password, is_active) VALUES (?, ?, ?, ?, ?, ?)',
                 [riderName, riderLastName, riderEmail, '03211234567', password, true]
             );
             riderId = res.insertId;
        } else {
            riderId = riders[0].id;
        }
        console.log('Rider ID:', riderId);

        // 4. Create Order
        const orderNumber = 'Ord2602120001';
        let [orders] = await conn.execute('SELECT id FROM orders WHERE order_number = ?', [orderNumber]);
        let orderId;
        
        if (orders.length === 0) {
            console.log('Creating order...');
            // Need a customer first
            let [customers] = await conn.execute('SELECT id FROM users WHERE user_type = "customer" LIMIT 1');
            let customerId;
            if (customers.length === 0) {
                 const [res] = await conn.execute(
                    'INSERT INTO users (first_name, last_name, email, password, user_type) VALUES (?, ?, ?, ?, ?)',
                    ['Test', 'Customer', 'customer@test.com', password, 'customer']
                );
                customerId = res.insertId;
            } else {
                customerId = customers[0].id;
            }

            const [res] = await conn.execute(
                'INSERT INTO orders (order_number, user_id, rider_id, store_id, total_amount, status, payment_method, payment_status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())',
                [orderNumber, customerId, riderId, storeId, 500, 'out_for_delivery', 'cod', 'pending']
            );
            orderId = res.insertId;
        } else {
            console.log('Order exists.');
            orderId = orders[0].id;
            // Update rider
            await conn.execute('UPDATE orders SET rider_id = ? WHERE id = ?', [riderId, orderId]);
        }
        console.log('Order ID:', orderId);

        // 5. Create Order Items
        // Ensure we have a product
        let [products] = await conn.execute('SELECT id FROM products WHERE store_id = ? LIMIT 1', [storeId]);
        let productId;
        if (products.length === 0) {
             const [res] = await conn.execute(
                 'INSERT INTO products (store_id, name, description, price, image_url, category_id) VALUES (?, ?, ?, ?, ?, ?)',
                 [storeId, 'Zinger Burger', 'Tasty', 250, 'burger.jpg', 1]
             );
             productId = res.insertId;
        } else {
            productId = products[0].id;
        }

        // Add item to order
        await conn.execute('DELETE FROM order_items WHERE order_id = ?', [orderId]);
        await conn.execute(
            'INSERT INTO order_items (order_id, product_id, store_id, quantity, price) VALUES (?, ?, ?, ?, ?)',
            [orderId, productId, storeId, 2, 250]
        );
        console.log('Order items created.');

        // 6. Ensure Admin exists
        const adminEmail = 'admin@servenow.pk';
        const [admins] = await conn.execute('SELECT id FROM users WHERE email = ?', [adminEmail]);
        if (admins.length === 0) {
            console.log('Creating admin...');
            await conn.execute(
                'INSERT INTO users (first_name, last_name, email, password, user_type, phone) VALUES (?, ?, ?, ?, ?, ?)',
                ['Super', 'Admin', adminEmail, password, 'admin', '03000000000']
            );
        } else {
            console.log('Admin exists.');
            // Update password just in case
            await conn.execute('UPDATE users SET password = ? WHERE id = ?', [password, admins[0].id]);
        }
        console.log('Admin ready.');

        await conn.end();
    } catch (err) {
        console.error(err);
    }
})();
