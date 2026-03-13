const mysql = require('mysql2/promise');
const dotenv = require('dotenv');
const path = require('path');

// Load environment variables
dotenv.config({ path: path.join(__dirname, '../.env') });

async function migrate() {
    console.log('Starting database migration...');
    
    const connection = await mysql.createConnection({
        host: process.env.DB_HOST,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME,
        port: process.env.DB_PORT || 3306
    });

    console.log('Connected to database.');

    async function hasColumn(table, column) {
        const [rows] = await connection.execute(
            'SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            [process.env.DB_NAME, table, column]
        );
        return rows && rows[0] && rows[0].cnt > 0;
    }

    try {
        // Migration for order_items.store_id
        const hasStoreId = await hasColumn('order_items', 'store_id');
        if (!hasStoreId) {
            console.log('Adding store_id to order_items...');
            await connection.execute('ALTER TABLE order_items ADD COLUMN store_id INT NULL');
            await connection.execute('ALTER TABLE order_items ADD FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE SET NULL');
            console.log('Successfully added store_id to order_items.');
        } else {
            console.log('store_id already exists in order_items.');
        }

        // Add other columns from routes/orders.js if they are missing
        const columnsToAdd = [
            { table: 'order_items', column: 'size_id', type: 'INT NULL' },
            { table: 'order_items', column: 'unit_id', type: 'INT NULL' },
            { table: 'order_items', column: 'variant_label', type: 'VARCHAR(255) NULL' }
        ];

        for (const item of columnsToAdd) {
            const exists = await hasColumn(item.table, item.column);
            if (!exists) {
                console.log(`Adding ${item.column} to ${item.table}...`);
                await connection.execute(`ALTER TABLE ${item.table} ADD COLUMN ${item.column} ${item.type}`);
                console.log(`Successfully added ${item.column} to ${item.table}.`);
            }
        }

    } catch (error) {
        console.error('Migration failed:', error);
    } finally {
        await connection.end();
        console.log('Database connection closed.');
    }
}

migrate();
