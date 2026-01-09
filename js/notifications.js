(function() {
    if (typeof io === 'undefined') {
        console.warn('Socket.IO client not loaded. Real-time notifications unavailable.');
        return;
    }

    // Connect to socket server
    const socket = io(API_BASE);

    function getCurrentUser() {
        try {
            const userData = localStorage.getItem('serveNowUser');
            return userData ? JSON.parse(userData) : null;
        } catch (e) {
            return null;
        }
    }

    socket.on('connect', () => {
        console.log('Connected to notification server');
        // Optional: Authenticate socket if needed in future
    });

    // Rider Notifications
    socket.on('rider_notification', (data) => {
        const user = getCurrentUser();
        if (user && user.user_type === 'rider' && user.id == data.rider_id) {
            showToast('New Assignment', data.message, 'info');
            
            // Play sound notification
            try {
                const audio = new Audio('https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3');
                audio.play().catch(e => console.log('Audio play failed:', e));
            } catch (e) {}

            // Refresh rider dashboard if function exists
            if (typeof displayRiderDeliveries === 'function') displayRiderDeliveries();
            if (typeof loadRiderWallet === 'function') loadRiderWallet();
        }
    });

    // User Notifications
    socket.on('user_notification', (data) => {
        const user = getCurrentUser();
        if (user && user.id == data.user_id) {
            showToast('Order Update', data.message, 'info');
            
            // Refresh orders if function exists (e.g. on orders.html)
            if (typeof displayOrders === 'function') displayOrders();
        }
    });

    // Order Status Updates (Generic)
    socket.on('order_status_update', (data) => {
        const user = getCurrentUser();
        if (user && user.id == data.user_id) {
            // Just refresh data, toast is handled by user_notification usually
            if (typeof displayOrders === 'function') displayOrders();
        }
    });

    // Payment Status Updates
    socket.on('payment_status_update', (data) => {
        const user = getCurrentUser();
        if (user && user.id == data.user_id) {
            if (typeof displayOrders === 'function') displayOrders();
        }
    });

    // Order Completed
    socket.on('order_completed', (data) => {
        const user = getCurrentUser();
        if (user && user.id == data.user_id) {
            showToast('Order Completed', data.message, 'success');
            if (typeof displayOrders === 'function') displayOrders();
        }
    });

})();
