const axios = require('axios');

const BASE_URL = 'http://66.163.116.74:3002';
const OWNER_EMAIL = 'owner@servenow.pk';
const OWNER_PASS = '123456';

(async () => {
    try {
        console.log('Attempting login as Store Owner...');
        const res = await axios.post(`${BASE_URL}/api/auth/login`, {
            email: OWNER_EMAIL,
            password: OWNER_PASS
        });
        
        console.log('Login successful!');
        console.log('User ID:', res.data.user.id);
        console.log('Token:', res.data.token.substring(0, 20) + '...');
        
        // Try to fetch the specific order to see details if allowed
        // But store owner can only see their orders.
        
    } catch (err) {
        console.error('Login failed:', err.response ? err.response.data : err.message);
    }
})();
