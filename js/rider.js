// Rider dashboard functionality

// Toast Notification System (copied from app.js)
function showToast(title, message, type = 'info', duration = 3000) {
    let container = document.getElementById('toastContainer');
    if (!container) {
        container = document.createElement('div');
        container.id = 'toastContainer';
        container.className = 'toast-container';
        document.body.appendChild(container);
    }

    const toastId = 'toast-' + Date.now();
    const toast = document.createElement('div');
    toast.id = toastId;
    toast.className = `toast ${type} slideIn`;
    toast.innerHTML = `
        <div class="toast-icon">
            ${type === 'success' ? '✓' : type === 'error' ? '✕' : type === 'warning' ? '!' : 'ℹ'}
        </div>
        <div class="toast-content">
            <div class="toast-title">${title}</div>
            <div class="toast-message">${message}</div>
        </div>
        <button class="toast-close" onclick="document.getElementById('${toastId}').remove()">×</button>
        <div class="toast-progress" style="animation: progressBar ${duration}ms linear forwards;"></div>
    `;
    container.appendChild(toast);

    setTimeout(() => {
        const elem = document.getElementById(toastId);
        if (elem) {
            elem.classList.remove('slideIn');
            elem.classList.add('slideOut');
            setTimeout(() => elem.remove(), 300);
        }
    }, duration);
}

function showSuccess(title, message, duration = 3000) {
    showToast(title, message, 'success', duration);
}

function showError(title, message, duration = 3000) {
    showToast(title, message, 'error', duration);
}

function showWarning(title, message, duration = 3000) {
    showToast(title, message, 'warning', duration);
}

function showInfo(title, message, duration = 3000) {
    showToast(title, message, 'info', duration);
}

let currentLocation = null;
let locationWatchId = null;
window._riderDeliveries = {};

// Get current location using GPS
function getCurrentLocation() {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            reject(new Error('Geolocation is not supported by this browser'));
            return;
        }

        // Check if we have permission
        if (navigator.permissions) {
            navigator.permissions.query({name:'geolocation'}).then(function(result) {
                if (result.state === 'denied') {
                    reject(new Error('Location permission denied. Please enable location access in your browser settings.'));
                    return;
                }
            });
        }

        navigator.geolocation.getCurrentPosition(
            (position) => {
                const location = `${position.coords.latitude.toFixed(6)}, ${position.coords.longitude.toFixed(6)}`;
                resolve(location);
            },
            (error) => {
                let errorMessage = 'Failed to get location: ';
                switch(error.code) {
                    case error.PERMISSION_DENIED:
                        errorMessage += 'Location permission denied. Please enable location access.';
                        break;
                    case error.POSITION_UNAVAILABLE:
                        errorMessage += 'Location information is unavailable.';
                        break;
                    case error.TIMEOUT:
                        errorMessage += 'Location request timed out.';
                        break;
                    default:
                        errorMessage += 'Unknown error occurred.';
                        break;
                }
                reject(new Error(errorMessage));
            },
            {
                enableHighAccuracy: true,
                timeout: 15000, // Increased timeout
                maximumAge: 300000 // 5 minutes
            }
        );
    });
}

// Start location tracking
function startLocationTracking() {
    if (locationWatchId) {
        navigator.geolocation.clearWatch(locationWatchId);
    }

    locationWatchId = navigator.geolocation.watchPosition(
        (position) => {
            currentLocation = `${position.coords.latitude.toFixed(6)}, ${position.coords.longitude.toFixed(6)}`;
            updateLocationDisplay();
        },
        (error) => {
            console.error('Location tracking error:', error);
        },
        {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 300000 // 5 minutes
        }
    );
}

// Stop location tracking
function stopLocationTracking() {
    if (locationWatchId) {
        navigator.geolocation.clearWatch(locationWatchId);
        locationWatchId = null;
    }
}

// Update location display on dashboard
function updateLocationDisplay() {
    const locationElement = document.getElementById('currentLocation');
    if (locationElement && currentLocation) {
        locationElement.textContent = currentLocation;
        locationElement.style.color = ''; // Reset color
    }
}

// Refresh location manually
function refreshLocation() {
    const locationElement = document.getElementById('currentLocation');
    if (locationElement) {
        locationElement.textContent = 'Getting location...';
        locationElement.style.color = '';
    }

    getCurrentLocation()
        .then((location) => {
            currentLocation = location;
            updateLocationDisplay();
            console.log('Location refreshed:', location);
            showSuccess('Location Updated', 'Location updated successfully!');
        })
        .catch((error) => {
            console.error('Failed to refresh location:', error);
            if (locationElement) {
                locationElement.textContent = 'Location unavailable - ' + error.message;
                locationElement.style.color = '#e53e3e';
            }
            showError('Error', 'Failed to get location: ' + error.message);
        });
}

// Auto-update location for active deliveries
async function autoUpdateLocation() {
    if (!currentLocation) return;

    try {
        // Get active deliveries
        const response = await fetch(`${API_BASE}/api/orders/rider/deliveries?status=assigned`, {
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            }
        });

        const data = await response.json();
        if (data.success && data.deliveries.length > 0) {
            // Update location for all active deliveries
            for (const delivery of data.deliveries) {
                await fetch(`${API_BASE}/api/orders/${delivery.id}/rider-location`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
                    },
                    body: JSON.stringify({ location: currentLocation })
                });
            }
        }
    } catch (error) {
        console.error('Error auto-updating location:', error);
    }
}

// Display rider's deliveries
async function displayRiderDeliveries(status = 'assigned', containerId = 'deliveriesContainer') {
    const deliveriesContainer = document.getElementById(containerId);
    if (!deliveriesContainer) return;

    try {
        const response = await fetch(`${API_BASE}/api/orders/rider/deliveries?status=${status}`, {
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            }
        });

        const data = await response.json();
        if (data.success) {
            deliveriesContainer.innerHTML = '';

            if (data.deliveries.length === 0) {
                deliveriesContainer.innerHTML = '<p>No deliveries found.</p>';
                return;
            }

            data.deliveries.forEach(delivery => {
                window._riderDeliveries[delivery.id] = delivery;
                const deliveryCard = document.createElement('div');
                deliveryCard.className = 'order-card';
                deliveryCard.innerHTML = `
                    <div class="order-header">
                        <h3>Order #${delivery.order_number}</h3>
                        <div class="order-header-actions" style="display:flex;align-items:center;gap:8px;">
                            <button class="btn btn-small" title="Order Info" onclick="openOrderInfo(${delivery.id})"><i class="fa fa-info-circle"></i></button>
                            <span class="order-status status-${delivery.status}">${delivery.status}</span>
                        </div>
                    </div>
                    <div class="order-details">
                        <p><strong>Customer:</strong> ${delivery.first_name} ${delivery.last_name}</p>
                        <p><strong>Store:</strong> ${delivery.store_name}</p>
                        <p><strong>Total:</strong> PKR ${delivery.total_amount}</p>
                        <p><strong>Delivery Address:</strong> ${delivery.delivery_address}</p>
                        <p><strong>Phone:</strong> ${delivery.phone || 'N/A'}</p>
                        ${delivery.phone ? `
                        <div class="contact-actions" style="margin: 8px 0; display: flex; gap: 8px; flex-wrap: wrap;">
                            <a class="btn btn-small" style="background:#2563eb;color:#fff;" href="tel:${delivery.phone}"><i class="fa fa-phone"></i> Call</a>
                            <a class="btn btn-small" style="background:#16a34a;color:#fff;" href="https://wa.me/${(delivery.phone || '').replace(/[^0-9]/g, '')}" target="_blank" rel="noopener"><i class="fa fa-whatsapp"></i> WhatsApp</a>
                            <a class="btn btn-small" style="background:#f59e0b;color:#fff;" href="sms:${delivery.phone}"><i class="fa fa-sms"></i> SMS</a>
                        </div>
                        ` : ''}
                        <p><strong>Payment Status:</strong> <span class="payment-status">${delivery.payment_status}</span></p>
                        <div class="order-items-summary" style="margin-top: 10px; padding-top: 10px; border-top: 1px dashed #ddd;">
                            <p><strong>Items:</strong></p>
                            <ul style="list-style: none; padding-left: 0;">
                                ${delivery.items && delivery.items.length > 0 ? delivery.items.map(item => `
                                    <li style="display: flex; justify-content: space-between; margin-bottom: 4px;">
                                        <span>${item.quantity}x ${item.product_name || 'Unknown Product'} ${item.variant_name ? `(${item.variant_name})` : ''}</span>
                                        <span>PKR ${item.price * item.quantity}</span>
                                    </li>
                                `).join('') : '<li>No items found</li>'}
                            </ul>
                        </div>
                        ${delivery.rider_location ? `<p><strong>My Location:</strong> ${delivery.rider_location}</p>` : ''}
                        ${delivery.estimated_delivery_time ? `<p><strong>Estimated Delivery:</strong> ${new Date(delivery.estimated_delivery_time).toLocaleString()}</p>` : ''}
                    </div>
                    <div class="order-actions">
                        ${delivery.status === 'out_for_delivery' ? `
                            <button onclick="updateMyLocation(${delivery.id})" class="btn btn-info">Update My Location</button>
                            <button onclick="markDelivered(${delivery.id})" class="btn btn-success">Mark as Delivered</button>
                            <button onclick="updatePaymentStatus(${delivery.id}, 'paid')" class="btn btn-primary">Mark Payment Received</button>
                        ` : `
                            <button onclick="viewDeliveryDetails(${delivery.id})" class="btn btn-primary">View Details</button>
                        `}
                    </div>
                `;
                deliveriesContainer.appendChild(deliveryCard);
            });
        } else {
            deliveriesContainer.innerHTML = '<p>Failed to load deliveries.</p>';
        }
    } catch (error) {
        console.error('Error loading deliveries:', error);
        deliveriesContainer.innerHTML = '<p>Error loading deliveries.</p>';
    }
}

// Update rider location manually (fallback)
async function updateMyLocation(orderId) {
    try {
        if (!currentLocation) {
            showWarning('Location Unavailable', 'Location not available. Please enable GPS and try again.');
            return;
        }

        const response = await fetch(`${API_BASE}/api/orders/${orderId}/rider-location`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ location: currentLocation })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Location Updated', 'Location updated successfully!');
            displayRiderDeliveries('assigned');
        } else {
            showError('Error', 'Failed to update location: ' + data.message);
        }
    } catch (error) {
        console.error('Error updating location:', error);
        showError('Error', 'Failed to update location.');
    }
}

// Mark delivery as completed
async function markDelivered(orderId) {
    if (!confirm('Are you sure the delivery is completed?')) return;

    try {
        const response = await fetch(`${API_BASE}/api/orders/${orderId}/deliver`, {
            method: 'PUT',
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            }
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Delivery Completed', 'Delivery marked as completed!');
            displayRiderDeliveries('assigned');
        } else {
            showError('Error', 'Failed to mark delivery as completed: ' + data.message);
        }
    } catch (error) {
        console.error('Error marking delivery as completed:', error);
        alert('Failed to mark delivery as completed.');
    }
}

// Update payment status
async function updatePaymentStatus(orderId, status) {
    if (!confirm('Confirm that payment has been received?')) return;

    try {
        const response = await fetch(`${API_BASE}/api/orders/${orderId}/payment-status`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ payment_status: status })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Payment Updated', 'Payment status updated!');
            displayRiderDeliveries('assigned');
        } else {
            showError('Error', 'Failed to update payment status: ' + data.message);
        }
    } catch (error) {
        console.error('Error updating payment status:', error);
        showError('Error', 'Failed to update payment status.');
    }
}

// View delivery details
function viewDeliveryDetails(orderId) {
    // For now, just show toast
    showInfo('Delivery Info', 'Delivery details for Order ID: ' + orderId);
}

// Load rider info
async function loadRiderInfo() {
    try {
        const response = await fetch(`${API_BASE}/api/orders/rider/profile`, {
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            }
        });

        const data = await response.json();
        if (data.success) {
            document.getElementById('riderName').textContent = `${data.rider.first_name} ${data.rider.last_name}`;
            document.getElementById('riderVehicle').textContent = data.rider.vehicle_type;
        }
    } catch (error) {
        console.error('Error loading rider info:', error);
    }
}

// Modal and tabs helpers
function createOrGetOrderInfoModal() {
    let modal = document.getElementById('orderInfoModal');
    if (modal) return modal;
    modal = document.createElement('div');
    modal.id = 'orderInfoModal';
    modal.className = 'modal';
    modal.innerHTML = `
        <div class="modal-content" style="max-width: 700px;">
            <span class="close" onclick="closeOrderInfoModal()">&times;</span>
            <div id="orderInfoBody"></div>
        </div>
    `;
    document.body.appendChild(modal);
    return modal;
}
function openOrderInfo(orderId) {
    const delivery = (window._riderDeliveries || {})[orderId];
    if (!delivery) return;
    const modal = createOrGetOrderInfoModal();
    const body = modal.querySelector('#orderInfoBody');
    const itemsHtml = (delivery.items || []).map(item => `
        <li style="display:flex;justify-content:space-between;margin-bottom:4px;">
            <span>${item.quantity}x ${item.product_name || 'Product'} ${item.variant_name ? '(' + item.variant_name + ')' : ''}</span>
            <span>PKR ${(item.price * item.quantity).toFixed(2)}</span>
        </li>
    `).join('');
    body.innerHTML = `
        <h3 style="margin-top:0;">Order #${delivery.order_number}</h3>
        <p><strong>Status:</strong> ${delivery.status}</p>
        <p><strong>Total:</strong> PKR ${Number(delivery.total_amount || 0).toFixed(2)} ${delivery.delivery_fee ? '(incl. delivery)' : ''}</p>
        <p><strong>Payment:</strong> ${delivery.payment_status || 'unknown'}</p>
        <p><strong>Customer:</strong> ${delivery.first_name || ''} ${delivery.last_name || ''}</p>
        <p><strong>Phone:</strong> ${delivery.phone || 'N/A'}</p>
        <p><strong>Address:</strong> ${delivery.delivery_address || 'N/A'}</p>
        <div style="margin-top:10px;border-top:1px solid #eee;padding-top:8px;">
            <p><strong>Items</strong></p>
            <ul style="list-style:none;padding-left:0;margin:0;">
                ${itemsHtml || '<li>No items found</li>'}
            </ul>
        </div>
    `;
    modal.style.display = 'block';
    setTimeout(() => modal.classList.add('show'), 10);
}
function closeOrderInfoModal() {
    const modal = document.getElementById('orderInfoModal');
    if (!modal) return;
    modal.classList.remove('show');
    setTimeout(() => { modal.style.display = 'none'; }, 200);
}

function setupRiderTabs() {
    try {
        const tabsBar = document.querySelector('.rider-tabs');
        if (tabsBar) {
            tabsBar.innerHTML = `
                <button id="tabBtnHome" class="tab active">Home</button>
                <button id="tabBtnHistory" class="tab">History</button>
                <button id="tabBtnWallet" class="tab">Wallet</button>
                <button id="tabBtnProfile" class="tab">Profile</button>
            `;
        }
        const deliveriesContainer = document.getElementById('deliveriesContainer');
        let tabsContent = document.getElementById('riderTabsContent');
        if (!tabsContent) {
            tabsContent = document.createElement('div');
            tabsContent.id = 'riderTabsContent';
            const parent = deliveriesContainer ? deliveriesContainer.parentElement : document.querySelector('.rider-section') || document.body;
            parent.insertBefore(tabsContent, deliveriesContainer);
        }
        tabsContent.innerHTML = `
            <div id="tabHomeContent"></div>
            <div id="tabHistoryContent" style="display:none;"></div>
            <div id="tabWalletContent" style="display:none;"></div>
            <div id="tabProfileContent" style="display:none;"></div>
        `;
        if (deliveriesContainer) {
            deliveriesContainer.id = 'tabHomeContent';
        }
        const bind = (btnId, cb) => {
            const btn = document.getElementById(btnId);
            if (btn) btn.addEventListener('click', cb);
        };
        bind('tabBtnHome', () => setActiveRiderTab('home'));
        bind('tabBtnHistory', () => setActiveRiderTab('history'));
        bind('tabBtnWallet', () => setActiveRiderTab('wallet'));
        bind('tabBtnProfile', () => setActiveRiderTab('profile'));
    } catch (e) {
        console.warn('setupRiderTabs failed', e);
    }
}
function setActiveRiderTab(name) {
    const btns = ['Home','History','Wallet','Profile'];
    btns.forEach(n => {
        const b = document.getElementById('tabBtn' + n);
        if (b) b.classList.toggle('active', n.toLowerCase() === name);
    });
    const contents = {
        home: 'tabHomeContent',
        history: 'tabHistoryContent',
        wallet: 'tabWalletContent',
        profile: 'tabProfileContent'
    };
    Object.keys(contents).forEach(k => {
        const el = document.getElementById(contents[k]);
        if (el) el.style.display = (k === name) ? 'block' : 'none';
    });
    if (name === 'home') {
        displayRiderDeliveries('assigned', 'tabHomeContent');
    } else if (name === 'history') {
        displayRiderDeliveries('completed', 'tabHistoryContent');
    } else if (name === 'wallet') {
        loadRiderWallet();
    } else if (name === 'profile') {
        loadRiderProfileTab();
    }
}
function loadRiderWallet() {
    const c = document.getElementById('tabWalletContent');
    if (!c) return;
    c.innerHTML = `
        <div class="card">
            <h3>Wallet</h3>
        displayRiderDeliveries('assigned', 'tabHomeContent');
    } else if (name === 'history') {
        displayRiderDeliveries('completed', 'tabHistoryContent');
    } else if (name === 'wallet') {
        loadRiderWallet();
    } else if (name === 'profile') {
        loadRiderProfileTab();
    }
}
function loadRiderWallet() {
    const c = document.getElementById('tabWalletContent');
    if (!c) return;
    c.innerHTML = `
        <div class="card">
            <h3>Wallet</h3>
            <p>Wallet details for riders are not configured yet.</p>
            <p>Please contact admin to enable rider wallet.</p>
        </div>
    `;
}
async function loadRiderProfileTab() {
    const c = document.getElementById('tabProfileContent');
    if (!c) return;
    try {
        const response = await fetch(`${API_BASE}/api/orders/rider/profile`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        if (data.success) {
            const r = data.rider || {};
            c.innerHTML = `
                <div class="card">
                    <h3>My Profile</h3>
                    <p><strong>Name:</strong> ${[r.first_name, r.last_name].filter(Boolean).join(' ')}</p>
                    <p><strong>Email:</strong> ${r.email || 'N/A'}</p>
                    <p><strong>Phone:</strong> ${r.phone || 'N/A'}</p>
                    <p><strong>Vehicle:</strong> ${r.vehicle_type || 'N/A'}</p>
                </div>
            `;
        } else {
            c.innerHTML = '<p>Failed to load profile.</p>';
        }
    } catch (e) {
        c.innerHTML = '<p>Error loading profile.</p>';
    }
}

// Initialize rider dashboard
document.addEventListener('DOMContentLoaded', function() {
    // Check if user is rider
    const userData = localStorage.getItem('serveNowUser');
    if (userData) {
        const user = JSON.parse(userData);
        if (user.user_type !== 'rider') {
            showError('Access Denied', 'Rider access required.');
            window.location.href = 'index.html';
            return;
        }
    } else {
        showWarning('Login Required', 'Please login as rider first.');
        window.location.href = 'login.html';
        return;
    }

    loadRiderInfo();
    setupRiderTabs();
    setActiveRiderTab('home');
    createOrGetOrderInfoModal();

    /* Location tracking disabled
    // Try to get initial location
    getCurrentLocation()
        .then((location) => {
            currentLocation = location;
            updateLocationDisplay();
            console.log('Initial location obtained:', location);
        })
        .catch((error) => {
            console.error('Failed to get initial location:', error);
            const locationElement = document.getElementById('currentLocation');
            if (locationElement) {
                locationElement.textContent = 'Location unavailable - ' + error.message;
                locationElement.style.color = '#e53e3e';
            }
            alert('Location access failed: ' + error.message + '\n\nPlease enable location permissions and refresh the page.');
        });

    // Start location tracking (will handle errors internally)
    startLocationTracking();

    // Auto-update location every 2 minutes
    setInterval(autoUpdateLocation, 120000); // 2 minutes
    */

    // Tab switching
    // legacy tab handlers removed in favor of new tabs

    // legacy tab handlers removed in favor of new tabs

    // Cleanup on page unload
    // window.addEventListener('beforeunload', stopLocationTracking);
});
