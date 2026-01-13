const db = require('../middleware/auth');

async function batchLoadOrderItems(database, orderIds) {
  if (!orderIds || orderIds.length === 0) return {};

  const placeholders = orderIds.map(() => '?').join(',');
  const [items] = await database.execute(`
    SELECT oi.*, p.name as product_name, p.image_url, p.store_id, s.name as item_store_name
    FROM order_items oi
    JOIN products p ON oi.product_id = p.id
    LEFT JOIN stores s ON oi.store_id = s.id
    WHERE oi.order_id IN (${placeholders})
    ORDER BY oi.order_id ASC
  `, orderIds);

  const itemsByOrderId = {};
  (items || []).forEach(item => {
    if (!itemsByOrderId[item.order_id]) {
      itemsByOrderId[item.order_id] = [];
    }
    itemsByOrderId[item.order_id].push(item);
  });

  return itemsByOrderId;
}

async function batchLoadStoreData(database, storeIds) {
  if (!storeIds || storeIds.length === 0) return {};

  const placeholders = storeIds.map(() => '?').join(',');
  const [stores] = await database.execute(`
    SELECT * FROM stores WHERE id IN (${placeholders})
  `, storeIds);

  const storeMap = {};
  (stores || []).forEach(store => {
    storeMap[store.id] = store;
  });

  return storeMap;
}

async function batchLoadRiderData(database, riderIds) {
  if (!riderIds || riderIds.length === 0) return {};

  const placeholders = riderIds.map(() => '?').join(',');
  const [riders] = await database.execute(`
    SELECT * FROM riders WHERE id IN (${placeholders})
  `, riderIds);

  const riderMap = {};
  (riders || []).forEach(rider => {
    riderMap[rider.id] = rider;
  });

  return riderMap;
}

async function batchLoadUserData(database, userIds) {
  if (!userIds || userIds.length === 0) return {};

  const placeholders = userIds.map(() => '?').join(',');
  const [users] = await database.execute(`
    SELECT id, first_name, last_name, email, phone, user_type FROM users WHERE id IN (${placeholders})
  `, userIds);

  const userMap = {};
  (users || []).forEach(user => {
    userMap[user.id] = user;
  });

  return userMap;
}

async function batchLoadProductData(database, productIds) {
  if (!productIds || productIds.length === 0) return {};

  const placeholders = productIds.map(() => '?').join(',');
  const [products] = await database.execute(`
    SELECT p.*, c.name as category_name 
    FROM products p
    LEFT JOIN categories c ON p.category_id = c.id
    WHERE p.id IN (${placeholders})
  `, productIds);

  const productMap = {};
  (products || []).forEach(product => {
    productMap[product.id] = product;
  });

  return productMap;
}

async function getPaginatedQuery(database, baseQuery, params, page = 1, pageSize = 20) {
  const offset = (page - 1) * pageSize;
  
  const [rows] = await database.execute(baseQuery + ` LIMIT ? OFFSET ?`, [...params, pageSize, offset]);
  
  const countQuery = baseQuery.replace(/SELECT.*?FROM/, 'SELECT COUNT(*) as total FROM');
  const [countResult] = await database.execute(countQuery, params);
  const total = countResult?.[0]?.total || 0;

  return {
    data: rows,
    pagination: {
      page,
      pageSize,
      total,
      pages: Math.ceil(total / pageSize)
    }
  };
}

module.exports = {
  batchLoadOrderItems,
  batchLoadStoreData,
  batchLoadRiderData,
  batchLoadUserData,
  batchLoadProductData,
  getPaginatedQuery
};
