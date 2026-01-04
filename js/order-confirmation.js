document.addEventListener('DOMContentLoaded', async () => {
    // Get order_number from URL
    const urlParams = new URLSearchParams(window.location.search);
    const orderNumber = urlParams.get('order_number');
    
    if (orderNumber) {
        const title = document.querySelector('h2');
        if (title) {
            title.textContent = `Order #${orderNumber} Placed!`;
        }

        // Fetch order details
        await fetchOrderDetails(orderNumber);
    }
    
    // Update cart count
    if (typeof updateCartCount === 'function') {
        updateCartCount();
    }
});

async function fetchOrderDetails(orderNumber) {
    const orderDetailsBox = document.getElementById('orderDetailsBox');
    const orderItemsContainer = document.getElementById('orderItems');
    const orderTotalSpan = document.getElementById('orderTotal');

    if (!orderDetailsBox || !orderItemsContainer || !orderTotalSpan) return;

    try {
        const token = localStorage.getItem('serveNowToken');
        if (!token) return;

        const response = await fetch(`${API_BASE}/api/orders/my-orders`, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });

        const data = await response.json();
        
        if (data.success && data.orders) {
            // Find the order with matching order_number
            // Note: order_number in DB might be string or int, compare loosely or safely
            const order = data.orders.find(o => String(o.order_number) === String(orderNumber));
            
            if (order) {
                // Display details
                orderDetailsBox.style.display = 'block';
                
                let itemsHtml = '';
                if (order.items && order.items.length > 0) {
                    order.items.forEach(item => {
                        itemsHtml += `
                            <div class="order-item-row" style="display: flex; justify-content: space-between; margin-bottom: 0.5rem;">
                                <span>${item.quantity}x ${item.product_name} ${item.variant_label ? `(${item.variant_label})` : ''}</span>
                                <span>PKR ${(parseFloat(item.price) * item.quantity).toFixed(2)}</span>
                            </div>
                        `;
                    });
                } else {
                    itemsHtml = '<p>No items found for this order.</p>';
                }
                
                orderItemsContainer.innerHTML = itemsHtml;
                orderTotalSpan.textContent = `PKR ${parseFloat(order.total_amount).toFixed(2)}`;
                
                // Add delivery info if available
                if (order.delivery_fee > 0) {
                    orderItemsContainer.innerHTML += `
                        <div class="order-item-row" style="display: flex; justify-content: space-between; margin-bottom: 0.5rem; color: var(--text-muted);">
                            <span>Delivery Fee</span>
                            <span>PKR ${parseFloat(order.delivery_fee).toFixed(2)}</span>
                        </div>
                    `;
                }
            }
        }
    } catch (error) {
        console.error('Error fetching order details:', error);
    }
}
