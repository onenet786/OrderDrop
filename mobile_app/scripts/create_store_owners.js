const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
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

        // 1. Get all stores with emails
        const [stores] = await connection.execute(
            "SELECT id, name, email FROM stores WHERE email IS NOT NULL AND email != ''"
        );
        console.log(`Found ${stores.length} stores with emails.`);

        // 2. Hash the password "12345678"
        const hashedPassword = await bcrypt.hash('12345678', 10);

        for (const store of stores) {
            const { id: storeId, name: storeName, email } = store;

            // 3. Check if user already exists
            const [users] = await connection.execute(
                'SELECT id FROM users WHERE email = ?',
                [email]
            );

            let userId;
            if (users.length > 0) {
                // User exists, update them to be store_owner and active
                userId = users[0].id;
                console.log(`Updating existing user ${email} (ID: ${userId})...`);
                await connection.execute(
                    `UPDATE users 
                     SET password = ?, user_type = 'store_owner', is_active = 1, is_verified = 1, store_id = ? 
                     WHERE id = ?`,
                    [hashedPassword, storeId, userId]
                );
            } else {
                // User does not exist, create them
                console.log(`Creating new user for ${email}...`);
                
                // Split store name for first/last name
                const nameParts = storeName.split(' ');
                const firstName = nameParts[0] || 'Store';
                const lastName = nameParts.slice(1).join(' ') || 'Owner';

                const [result] = await connection.execute(
                    `INSERT INTO users (first_name, last_name, email, password, phone, address, user_type, is_active, is_verified, store_id)
                     VALUES (?, ?, ?, ?, '0000000000', 'Store Address', 'store_owner', 1, 1, ?)`,
                    [firstName, lastName, email, hashedPassword, storeId]
                );
                userId = result.insertId;
            }

            // 4. Update store to point to this owner
            await connection.execute(
                'UPDATE stores SET owner_id = ? WHERE id = ?',
                [userId, storeId]
            );
            console.log(`Assigned Store "${storeName}" (ID: ${storeId}) to User ID: ${userId}`);
        }

        console.log('Done processing all stores.');

    } catch (e) {
        console.error('Error:', e);
    } finally {
        if (connection) await connection.end();
    }
}

run();
