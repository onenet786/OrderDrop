(function() {
    if (typeof io === 'undefined') {
        console.warn('Socket.IO client not loaded. Real-time notifications unavailable.');
        return;
    }

    // Ensure API_BASE is properly set
    const socketUrl = API_BASE || window.location.origin;
    const socket = io(socketUrl, {
        reconnection: true,
        reconnectionDelay: 1000,
        reconnectionDelayMax: 5000,
        reconnectionAttempts: 5
    });

    function emitUserIdentification() {
        const user = getCurrentUser();
        if (user && socket.connected) {
            socket.emit('identify_user', {
                user_id: user.id,
                user_type: user.user_type
            });
            console.log(`[Socket] Identified as user ${user.id} (${user.user_type})`, 'Socket ID:', socket.id);
        }
    }

    socket.on('connect', () => {
        console.log('[Socket] Connected to server. Socket ID:', socket.id);
        emitUserIdentification();
    });

    socket.on('reconnect', () => {
        console.log('[Socket] Reconnected to server. Socket ID:', socket.id);
        emitUserIdentification();
    });

    function playNotificationSound() {
        try {
            // Mixkit notification sound
            const audio = new Audio('https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3');
            audio.play().catch(e => console.log('Audio play failed:', e));
        } catch (e) {
            console.error('Error playing sound:', e);
        }
    }

    function getCurrentUser() {
        try {
            const userData = localStorage.getItem('serveNowUser');
            return userData ? JSON.parse(userData) : null;
        } catch (e) {
            return null;
        }
    }



    // Admin Notifications: New Order
    socket.on('new_order', (data) => {
        const user = getCurrentUser();
        if (user && user.user_type === 'admin') {
            showToast('New Order Received', `Order ${data.order_number} has been placed. Amount: PKR ${data.total_amount}`, 'success');
            playNotificationSound();
            
            // Refresh admin dashboards if present
            if (typeof loadOrders === 'function') loadOrders();
            if (typeof loadDashboardStats === 'function') loadDashboardStats();
        }
    });

    // Rider Notifications
    socket.on('rider_notification', (data) => {
        const user = getCurrentUser();
        if (user && user.user_type === 'rider' && user.id == data.rider_id) {
            showToast('New Assignment', data.message, 'info');
            playNotificationSound();
            
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
            playNotificationSound();
            
            // Refresh orders if function exists (e.g. on orders.html)
            if (typeof displayOrders === 'function') displayOrders();
        }
    });

    // Order Status Updates (Generic)
    socket.on('order_status_update', (data) => {
        const user = getCurrentUser();
        if (user && (user.id == data.user_id || user.user_type === 'admin')) {
            // Refresh data for both User and Admin
            if (typeof displayOrders === 'function') displayOrders();
            if (typeof loadOrders === 'function') loadOrders();
            
            // If admin, we might want a toast for delivered orders too
            if (user.user_type === 'admin' && data.status === 'delivered') {
                showToast('Order Delivered', `Order ${data.order_number} has been marked as delivered.`, 'info');
                playNotificationSound();
            }
        }
    });

    // Payment Status Updates
    socket.on('payment_status_update', (data) => {
        const user = getCurrentUser();
        if (user && (user.id == data.user_id || user.user_type === 'admin')) {
            if (typeof displayOrders === 'function') displayOrders();
            if (typeof loadOrders === 'function') loadOrders();
            
            if (user.user_type === 'admin' && data.payment_status === 'paid') {
                showToast('Payment Received', `Payment for order ${data.order_number} has been confirmed.`, 'success');
                playNotificationSound();
            }
        }
    });

    // Order Completed
    socket.on('order_completed', (data) => {
        const user = getCurrentUser();
        if (user && user.id == data.user_id) {
            showToast('Order Completed', data.message || 'Your order is completed. Thank you!', 'success');
            playNotificationSound();
            if (typeof displayOrders === 'function') displayOrders();
        }
        
        if (user && user.user_type === 'admin') {
            showToast('Order Fully Completed', `Order ${data.order_number} is now delivered and paid.`, 'success');
            playNotificationSound();
            if (typeof loadOrders === 'function') loadOrders();
        }
    });

})();
