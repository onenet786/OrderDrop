const mysql = require('mysql2/promise');
require('dotenv').config();

async function updateSchema() {
  const connection = await mysql.createConnection({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'servenow',
    port: process.env.DB_PORT || 3306
  });

  console.log('Checking for columns...');

  try {
    // Check if settlement_id exists in order_items
    const [oiCols] = await connection.execute("SHOW COLUMNS FROM order_items LIKE 'settlement_id'");
    if (oiCols.length === 0) {
      console.log('Adding settlement_id to order_items...');
      await connection.execute("ALTER TABLE order_items ADD COLUMN settlement_id INT DEFAULT NULL");
      await connection.execute("CREATE INDEX idx_order_items_settlement_id ON order_items(settlement_id)");
      console.log('settlement_id added.');
    } else {
      console.log('settlement_id already exists.');
    }

    // Check if commission_rate exists in stores
    const [storeCols] = await connection.execute("SHOW COLUMNS FROM stores LIKE 'commission_rate'");
    if (storeCols.length === 0) {
      console.log('Adding commission_rate to stores...');
      await connection.execute("ALTER TABLE stores ADD COLUMN commission_rate DECIMAL(5, 2) DEFAULT 10.00");
      console.log('commission_rate added.');
    } else {
      console.log('commission_rate already exists.');
    }
    
  } catch (err) {
    console.error('Schema update error:', err);
  } finally {
    await connection.end();
  }
}
updateSchema();
