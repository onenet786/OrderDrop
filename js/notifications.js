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

    // Notification bell management
    const notificationsStore = [];
    const MAX_NOTIFICATIONS = 20;

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

    // Notification Bell UI Management
    function initNotificationBell() {
        const bellBtn = document.getElementById('notificationBellBtn');
        const dropdown = document.getElementById('notificationDropdown');
        const clearBtn = document.getElementById('clearNotificationsBtn');

        if (!bellBtn || !dropdown) return;

        // Toggle dropdown
        bellBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            dropdown.classList.toggle('active');
            bellBtn.classList.toggle('active');
        });

        // Close dropdown when clicking outside
        document.addEventListener('click', (e) => {
            if (!e.target.closest('.notification-bell-container')) {
                dropdown.classList.remove('active');
                bellBtn.classList.remove('active');
            }
        });

        // Clear notifications
        if (clearBtn) {
            clearBtn.addEventListener('click', (e) => {
                e.preventDefault();
                notificationsStore.length = 0;
                renderNotifications();
            });
        }

        // Close dropdown when selecting a notification
        dropdown.addEventListener('click', (e) => {
            if (e.target.closest('.notification-item')) {
                dropdown.classList.remove('active');
                bellBtn.classList.remove('active');
            }
        });
    }

    function addNotification(title, message, type = 'info', icon = 'fa-info-circle') {
        const notification = {
            id: Date.now(),
            title,
            message,
            type,
            icon,
            timestamp: new Date(),
            unread: true
        };

        notificationsStore.unshift(notification);

        // Keep only last 20 notifications
        if (notificationsStore.length > MAX_NOTIFICATIONS) {
            notificationsStore.pop();
        }

        renderNotifications();
        updateBadge();
        playNotificationSound();
    }

    function renderNotifications() {
        const list = document.getElementById('notificationList');
        if (!list) return;

        if (notificationsStore.length === 0) {
            list.innerHTML = `
                <div class="notification-empty">
                    <i class="fas fa-bell-slash"></i>
                    <p>No notifications</p>
                </div>
            `;
            return;
        }

        list.innerHTML = notificationsStore.map((notif) => {
            const timeAgo = getTimeAgo(notif.timestamp);
            return `
                <div class="notification-item ${notif.unread ? 'unread' : ''}">
                    <i class="fas ${notif.icon} notification-icon"></i>
                    <div class="notification-content">
                        <div class="notification-title">${escapeHtml(notif.title)}</div>
                        <div class="notification-message">${escapeHtml(notif.message)}</div>
                        <div class="notification-time">${timeAgo}</div>
                    </div>
                </div>
            `;
        }).join('');
    }

    function updateBadge() {
        const unreadCount = notificationsStore.filter(n => n.unread).length;
        const badge = document.getElementById('notificationBadge');
        
        if (badge) {
            if (unreadCount > 0) {
                badge.textContent = unreadCount > 99 ? '99+' : unreadCount;
                badge.style.display = 'flex';
            } else {
                badge.style.display = 'none';
            }
        }
    }

    function getTimeAgo(date) {
        const seconds = Math.floor((new Date() - date) / 1000);
        
        if (seconds < 60) return 'Just now';
        if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
        if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
        return `${Math.floor(seconds / 86400)}d ago`;
    }

    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }



    // Admin Notifications: New Order
    socket.on('new_order', (data) => {
        const user = getCurrentUser();
        if (user && user.user_type === 'admin') {
            addNotification(
                'New Order Received',
                `Order ${data.order_number} - PKR ${data.total_amount}`,
                'success',
                'fa-shopping-bag'
            );
            showToast('New Order Received', `Order ${data.order_number} has been placed. Amount: PKR ${data.total_amount}`, 'success');
            
            // Refresh admin dashboards if present
            if (typeof loadOrders === 'function') loadOrders();
            if (typeof loadDashboardStats === 'function') loadDashboardStats();
        }
    });

    // Rider Notifications
    socket.on('rider_notification', (data) => {
        const user = getCurrentUser();
        if (user && user.user_type === 'rider' && user.id == data.rider_id) {
            addNotification(
                'New Assignment',
                data.message,
                'info',
                'fa-tasks'
            );
            showToast('New Assignment', data.message, 'info');
            
            // Refresh rider dashboard if function exists
            if (typeof displayRiderDeliveries === 'function') displayRiderDeliveries();
            if (typeof loadRiderWallet === 'function') loadRiderWallet();
        }
    });

    // User Notifications
    socket.on('user_notification', (data) => {
        const user = getCurrentUser();
        if (user && user.id == data.user_id) {
            addNotification(
                'Order Update',
                data.message,
                'info',
                'fa-box'
            );
            showToast('Order Update', data.message, 'info');
            
            // Refresh orders if function exists (e.g. on orders.html)
            if (typeof displayOrders === 'function') displayOrders();
        }
    });

    // Order Status Updates (Generic)
    socket.on('order_status_update', (data) => {
        const user = getCurrentUser();
        if (user && (user.id == data.user_id || user.user_type === 'admin')) {
            // Add to bell notifications
            let icon = 'fa-clock';
            if (data.status === 'delivered') icon = 'fa-check-circle';
            if (data.status === 'confirmed') icon = 'fa-check';
            
            addNotification(
                `Order ${data.status.charAt(0).toUpperCase() + data.status.slice(1)}`,
                `Order ${data.order_number}`,
                'info',
                icon
            );

            // Refresh data for both User and Admin
            if (typeof displayOrders === 'function') displayOrders();
            if (typeof loadOrders === 'function') loadOrders();
            
            // If admin, we might want a toast for delivered orders too
            if (user.user_type === 'admin' && data.status === 'delivered') {
                showToast('Order Delivered', `Order ${data.order_number} has been marked as delivered.`, 'info');
            }
        }
    });

    // Payment Status Updates
    socket.on('payment_status_update', (data) => {
        const user = getCurrentUser();
        if (user && (user.id == data.user_id || user.user_type === 'admin')) {
            addNotification(
                'Payment ' + (data.payment_status === 'paid' ? 'Received' : 'Update'),
                `Order ${data.order_number}`,
                data.payment_status === 'paid' ? 'success' : 'info',
                data.payment_status === 'paid' ? 'fa-check-circle' : 'fa-money-bill'
            );

            if (typeof displayOrders === 'function') displayOrders();
            if (typeof loadOrders === 'function') loadOrders();
            
            if (user.user_type === 'admin' && data.payment_status === 'paid') {
                showToast('Payment Received', `Payment for order ${data.order_number} has been confirmed.`, 'success');
            }
        }
    });

    // Order Completed
    socket.on('order_completed', (data) => {
        const user = getCurrentUser();
        if (user && user.id == data.user_id) {
            addNotification(
                'Order Completed',
                data.message || 'Your order has been delivered. Thank you!',
                'success',
                'fa-check-circle'
            );
            showToast('Order Completed', data.message || 'Your order is completed. Thank you!', 'success');
            if (typeof displayOrders === 'function') displayOrders();
        }
        
        if (user && user.user_type === 'admin') {
            addNotification(
                'Order Fully Completed',
                `Order ${data.order_number}`,
                'success',
                'fa-check-double'
            );
            showToast('Order Fully Completed', `Order ${data.order_number} is now delivered and paid.`, 'success');
            if (typeof loadOrders === 'function') loadOrders();
        }
    });

    // Initialize notification bell when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initNotificationBell);
    } else {
        initNotificationBell();
    }

})();
