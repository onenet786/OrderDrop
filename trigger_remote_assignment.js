const axios = require('axios');

const BASE_URL = 'http://23.137.84.249:3002';
const ADMIN_EMAIL = 'admin@servenow.com';
const ADMIN_PASS = 'Admin786';
const ORDER_ID = 30; // From previous output
const RIDER_ID = 21; // Assuming rider exists, otherwise we'll fetch one

(async () => {
    try {
        console.log('Logging in as admin...');
        const loginRes = await axios.post(`${BASE_URL}/api/auth/login`, {
            email: ADMIN_EMAIL,
            password: ADMIN_PASS
        });
        
        const token = loginRes.data.token;
        console.log('Logged in.');

        console.log('Fetching available riders...');
        const ridersRes = await axios.get(`${BASE_URL}/api/riders`, {
            headers: { Authorization: `Bearer ${token}` }
        });
        
        const activeRiders = ridersRes.data.riders.filter(r => r.is_active);
        console.log(`Found ${activeRiders.length} active riders.`);
        
        if (activeRiders.length === 0) {
            console.log('No active riders found! Cannot assign.');
            return;
        }

        const rider = activeRiders[0];
        console.log(`Assigning rider ${rider.id} (${rider.first_name}) to order ${ORDER_ID}...`);

        const assignRes = await axios.put(
            `${BASE_URL}/api/orders/${ORDER_ID}/assign-rider`,
            { rider_id: rider.id },
            { headers: { Authorization: `Bearer ${token}` } }
        );

        console.log('Assignment response:', assignRes.data);

        // We can't see the server logs remotely, so we have to rely on user feedback
        // OR we can check if we can log in as the Store Owner of Store 88 ("Pathan Chapli Kabab")
        // and check if they received a notification via socket.
        // But we don't have the Store Owner's password.
        
        // However, we can check if the system throws an error.

    } catch (err) {
        console.error('Error:', err.response ? err.response.data : err.message);
    }
})();
