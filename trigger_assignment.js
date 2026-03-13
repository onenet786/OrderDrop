const axios = require('axios');
const fs = require('fs');
const path = require('path');

const BASE_URL = 'http://23.137.84.249:3002';
const ADMIN_EMAIL = 'admin@servenow.pk';
const ADMIN_PASS = '123456';
const ORDER_ID = 1; // From fix_data.js
const RIDER_ID = 21; // From fix_data.js

(async () => {
    try {
        console.log('Logging in as admin...');
        const loginRes = await axios.post(`${BASE_URL}/api/auth/login`, {
            email: ADMIN_EMAIL,
            password: ADMIN_PASS
        });
        
        const token = loginRes.data.token;
        console.log('Logged in. Token:', token.substring(0, 20) + '...');

        console.log(`Assigning rider ${RIDER_ID} to order ${ORDER_ID}...`);
        
        // Clear log file first
        const logPath = path.join(__dirname, 'socket_debug.log');
        if (fs.existsSync(logPath)) {
            fs.writeFileSync(logPath, '');
        }

        const assignRes = await axios.put(
            `${BASE_URL}/api/orders/${ORDER_ID}/assign-rider`,
            { rider_id: RIDER_ID },
            { headers: { Authorization: `Bearer ${token}` } }
        );

        console.log('Assignment response:', assignRes.data);

        // Wait a bit for socket events to process and log
        await new Promise(resolve => setTimeout(resolve, 2000));

        console.log('Checking socket_debug.log...');
        if (fs.existsSync(logPath)) {
            const logs = fs.readFileSync(logPath, 'utf8');
            console.log('--- LOG CONTENT ---');
            console.log(logs);
            console.log('-------------------');
        } else {
            console.log('Log file not found!');
        }

    } catch (err) {
        console.error('Error:', err.response ? err.response.data : err.message);
    }
})();
