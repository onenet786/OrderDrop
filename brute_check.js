const axios = require('axios');

const BASE_URL = 'http://23.137.84.249:3002';

const USERS = [
    { email: 'admin@servenow.com', pass: 'Admin786' }
];

(async () => {
    for (const user of USERS) {
        try {
            console.log(`Trying ${user.email} / ${user.pass}...`);
            const res = await axios.post(`${BASE_URL}/api/auth/login`, {
                email: user.email,
                password: user.pass
            });
            console.log(`SUCCESS! Token: ${res.data.token.substring(0, 10)}...`);
            
            // If success, try to fetch order
            if (res.data.user.user_type === 'admin') {
                await checkOrderAsAdmin(res.data.token);
            }
            break; // Stop after first success
        } catch (err) {
            console.log('Failed:', err.response ? err.response.data.message : err.message);
        }
    }
})();

async function checkOrderAsAdmin(token) {
    try {
        console.log('Fetching all orders to find ID...');
        const res = await axios.get(`${BASE_URL}/api/orders?limit=100`, {
            headers: { Authorization: `Bearer ${token}` }
        });
        
        const targetOrder = res.data.orders.find(o => o.order_number === 'Ord2602120001');
        
        if (targetOrder) {
            console.log(`Found Order ID: ${targetOrder.id}`);
            console.log('Fetching details...');
            const detailRes = await axios.get(`${BASE_URL}/api/orders/${targetOrder.id}`, {
                headers: { Authorization: `Bearer ${token}` }
            });
            
            const order = detailRes.data.order;
            console.log('Order Items:', JSON.stringify(order.items, null, 2));
            console.log('Store Wise Items:', JSON.stringify(order.store_wise_items, null, 2));
        } else {
            console.log('Order Ord2602120001 not found in recent list.');
        }
    } catch (e) {
        console.error('Error checking order:', e.message);
    }
}
