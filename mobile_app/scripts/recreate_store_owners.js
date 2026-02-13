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

        console.log('1. Unlinking owners from stores...');
        await connection.execute('UPDATE stores SET owner_id = NULL');

        console.log('2. Cleaning up old store_owner data...');
        // Try to delete wallets first to avoid FK constraints
        try {
            await connection.execute("DELETE FROM wallets WHERE user_id IN (SELECT id FROM users WHERE user_type = 'store_owner')");
            console.log('Deleted wallets for store owners.');
        } catch (e) {
            console.warn('Warning: Could not delete wallets:', e.message);
        }

        // Now try to delete users
        try {
            const [deleteResult] = await connection.execute("DELETE FROM users WHERE user_type = 'store_owner'");
            console.log(`Deleted ${deleteResult.affectedRows} existing store_owner users.`);
        } catch (e) {
            console.warn('Warning: Could not delete some users due to foreign key constraints. Proceeding to update/create...');
            console.warn('Error details:', e.message);
        }

        // 3. Get all stores with emails
        const [stores] = await connection.execute(
            "SELECT id, name, email FROM stores WHERE email IS NOT NULL AND email != ''"
        );
        console.log(`Found ${stores.length} stores with emails.`);

        // 4. Hash the password "12345678"
        const hashedPassword = await bcrypt.hash('12345678', 10);

        for (const store of stores) {
            const { id: storeId, name: storeName, email } = store;

            // Check if user exists (might remain if delete failed)
            const [users] = await connection.execute(
                'SELECT id FROM users WHERE email = ?',
                [email]
            );

            let userId;
            if (users.length > 0) {
                // User exists (delete failed or re-using email), update them
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

            // 5. Update store to point to this owner
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
