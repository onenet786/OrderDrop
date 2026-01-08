const express = require('express');
const { body, validationResult } = require('express-validator');
const { authenticateToken, requireAdmin, requireStoreOwner } = require('../middleware/auth');

const router = express.Router();

async function hasColumn(db, table, column) {
    const [rows] = await db.execute(
        'SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        [table, column]
    );
    return rows && rows[0] && rows[0].cnt > 0;
}

async function ensureOrderItemsSchema(db) {
    const columns = [
        { name: 'size_id', definition: 'INT NULL' },
        { name: 'unit_id', definition: 'INT NULL' },
        { name: 'variant_label', definition: 'VARCHAR(255) NULL' },
        { name: 'store_id', definition: 'INT NULL', constraint: 'FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE SET NULL' }
    ];

    for (const col of columns) {
        try {
            const exists = await hasColumn(db, 'order_items', col.name);
            if (!exists) {
                await db.execute(`ALTER TABLE order_items ADD COLUMN ${col.name} ${col.definition}`);
                if (col.constraint) {
                    try {
                        await db.execute(`ALTER TABLE order_items ADD ${col.constraint}`);
                    } catch (err) {
                        // Constraint might already exist or fail for other reasons
                    }
                }
            }
        } catch (e) {
            console.error(`Failed to ensure column ${col.name}:`, e);
        }
    }
}

async function ensureOrdersParentColumn(db) {
    try {
        // Try to select the column to check existence (more robust than information_schema)
        await db.execute('SELECT parent_order_number FROM orders LIMIT 1');
    } catch (e) {
        // If error is about missing column, add it
        if (e.code === 'ER_BAD_FIELD_ERROR' || (e.message && e.message.includes('Unknown column'))) {
            try {
                await db.execute('ALTER TABLE orders ADD COLUMN parent_order_number VARCHAR(50) NULL');
                try {
                    await db.execute('CREATE INDEX idx_orders_parent_order_number ON orders(parent_order_number)');
                } catch (idxErr) {
                    // Ignore index creation error
                }
            } catch (alterErr) {
                console.error('Failed to add parent_order_number column:', alterErr);
            }
        }
    }
}

async function ensureOrdersStoreIdNullable(db) {
    try {
        // Check if store_id is nullable (simplified: just try to modify it)
        await db.execute('ALTER TABLE orders MODIFY COLUMN store_id INT NULL');
    } catch (e) {
        // Ignore if already nullable or other non-critical errors
        // console.error('Failed to make store_id nullable:', e);
    }
}

async function ensureRiderLocationColumns(db) {
    try {
        const hasRiderLatitude = await hasColumn(db, 'orders', 'rider_latitude');
        if (!hasRiderLatitude) {
            await db.execute('ALTER TABLE orders ADD COLUMN rider_latitude DECIMAL(10, 8) NULL');
        }
    } catch (e) {
        console.error('Failed to add rider_latitude column:', e);
    }

    try {
        const hasRiderLongitude = await hasColumn(db, 'orders', 'rider_longitude');
        if (!hasRiderLongitude) {
            await db.execute('ALTER TABLE orders ADD COLUMN rider_longitude DECIMAL(11, 8) NULL');
        }
    } catch (e) {
        console.error('Failed to add rider_longitude column:', e);
    }
}

// Get user's orders
router.get('/my-orders', authenticateToken, async (req, res) => {
    try {
        await ensureOrderItemsSchema(req.db);
        // await ensureOrdersParentColumn(req.db); // Not strictly needed if we don't use it for grouping anymore
        
        const [orders] = await req.db.execute(`
            SELECT o.*, s.name as store_name, s.location as store_location,
                   r.first_name as rider_first_name, r.last_name as rider_last_name, r.phone as rider_phone
            FROM orders o
            LEFT JOIN stores s ON o.store_id = s.id
            LEFT JOIN riders r ON o.rider_id = r.id
            WHERE o.user_id = ?
            ORDER BY o.created_at DESC
        `, [req.user.id]);

        // Get order items for each order
        for (let order of orders) {
            const [items] = await req.db.execute(`
                SELECT oi.*, p.name as product_name, p.image_url, p.store_id, s.name as item_store_name
                FROM order_items oi
                JOIN products p ON oi.product_id = p.id
                LEFT JOIN stores s ON oi.store_id = s.id
                WHERE oi.order_id = ?
            `, [order.id]);
            order.items = items;
            
            // If store_id is NULL (multi-store order), set display name
            if (!order.store_id) {
                order.store_name = 'Multiple Stores';
                order.is_group = true; // reusing existing frontend logic
                
                // Group items by store for display if needed, or just let frontend handle it
                // We can construct sub_orders mock structure for frontend compatibility
                const storeGroups = {};
                items.forEach(item => {
                    if (!storeGroups[item.store_id]) {
                        storeGroups[item.store_id] = {
                            store_name: item.item_store_name,
                            status: order.status, // Inherit main order status
                            items: []
                        };
                    }
                    storeGroups[item.store_id].items.push(item);
                });
                order.sub_orders = Object.values(storeGroups);
            }
        }

        res.json({
            success: true,
            orders: orders
        });

    } catch (error) {
        console.error('Error fetching orders:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch orders',
            error: error.message
        });
    }
});

// Test notification endpoint
router.get('/test-notification', (req, res) => {
    try {
        const fs = require('fs');
        const path = require('path');
        const logEvent = (msg) => {
            fs.appendFileSync(path.join(__dirname, '../socket_debug.log'), `[${new Date().toISOString()}] ${msg}\n`);
        };

        logEvent(`Attempting to emit TEST notification. req.io present: ${!!req.io}`);
        if (req.io) {
            req.io.emit('new_order', {
                id: 0,
                order_number: 'TEST-SOCKET',
                total_amount: 0.00,
                created_at: new Date()
            });
            logEvent('TEST notification emitted');
            return res.json({ success: true, message: 'Test notification emitted' });
        }
        logEvent('ERROR: req.io not found for TEST notification');
        res.status(500).json({ success: false, message: 'req.io not found' });
    } catch (e) {
        res.status(500).json({ success: false, error: e.message });
    }
});

// Create new order
router.post('/', authenticateToken, async (req, res) => {
    try {
        const {
            items,
            delivery_address,
            delivery_time,
            payment_method,
            special_instructions
        } = req.body;

        if (!items || items.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'Order must contain at least one item'
            });
        }

        if (!delivery_address || delivery_address.trim() === '') {
            return res.status(400).json({
                success: false,
                message: 'Delivery address is required'
            });
        }

        if (!payment_method) {
            return res.status(400).json({
                success: false,
                message: 'Payment method is required'
            });
        }

        // Generate Order Number: Ordyymmddxxxx
        const now = new Date();
        const yy = String(now.getFullYear()).slice(-2);
        const mm = String(now.getMonth() + 1).padStart(2, '0');
        const dd = String(now.getDate()).padStart(2, '0');
        const datePart = `${yy}${mm}${dd}`;
        const prefix = `Ord${datePart}`;
        
        const [rows] = await req.db.execute(
            'SELECT order_number FROM orders WHERE order_number LIKE ? ORDER BY order_number DESC LIMIT 1',
            [`${prefix}%`]
        );
        
        let sequence = 1;
        if (rows && rows.length > 0) {
            const lastOrderNumber = rows[0].order_number;
            const lastSequenceStr = lastOrderNumber.slice(-4);
            if (/^\d{4}$/.test(lastSequenceStr)) {
                sequence = parseInt(lastSequenceStr, 10) + 1;
            }
        }
        
        const order_number = `${prefix}${String(sequence).padStart(4, '0')}`;
        
        // Validate and prepare items
        const preparedItems = [];
        const storeIds = new Set();
        let itemsSubtotal = 0;

        for (let item of items) {
            const productId = parseInt(String(item.product_id), 10);
            const quantity = parseInt(String(item.quantity), 10);
            const sizeId = item.size_id === null || item.size_id === undefined ? null : parseInt(String(item.size_id), 10);
            const unitId = item.unit_id === null || item.unit_id === undefined ? null : parseInt(String(item.unit_id), 10);
            const providedVariantLabel = item.variant_label ? String(item.variant_label) : null;

            if (!Number.isInteger(productId) || productId <= 0 || !Number.isInteger(quantity) || quantity <= 0) {
                return res.status(400).json({ success: false, message: 'Invalid order item payload' });
            }

            const [products] = await req.db.execute(
                'SELECT id, price, store_id, name, size_id, unit_id FROM products WHERE id = ? AND is_available = true',
                [productId]
            );

            if (!products || products.length === 0) {
                return res.status(400).json({ success: false, message: `Product ${productId} not found or not available` });
            }

            const product = products[0];
            storeIds.add(product.store_id);
            let unitPrice = Number(product.price);
            let variantLabel = providedVariantLabel;

            if (sizeId || unitId) {
                let query = `
                    SELECT psp.price, sz.label as size_label, u.name as unit_name, u.abbreviation as unit_abbreviation
                    FROM product_size_prices psp
                    LEFT JOIN sizes sz ON psp.size_id = sz.id
                    LEFT JOIN units u ON psp.unit_id = u.id
                    WHERE psp.product_id = ?
                `;
                const params = [productId];

                if (sizeId && unitId) {
                    query += " AND psp.size_id = ? AND psp.unit_id = ?";
                    params.push(sizeId, unitId);
                } else if (sizeId) {
                    query += " AND psp.size_id = ? AND psp.unit_id IS NULL";
                    params.push(sizeId);
                } else if (unitId) {
                    query += " AND psp.unit_id = ? AND psp.size_id IS NULL";
                    params.push(unitId);
                }

                query += " LIMIT 1";

                const [rows] = await req.db.execute(query, params);
                
                if (rows && rows.length > 0) {
                    unitPrice = Number(rows[0].price);
                    if (!variantLabel) {
                        const sizeLabel = rows[0].size_label ? String(rows[0].size_label) : '';
                        const unitLabel = rows[0].unit_abbreviation || rows[0].unit_name ? String(rows[0].unit_abbreviation || rows[0].unit_name) : '';
                        variantLabel = (sizeLabel && unitLabel) ? `${sizeLabel} ${unitLabel}` : (sizeLabel || unitLabel || null);
                    }
                } else {
                    // Fallback: Check if requested variant matches the base product's size/unit
                    const productSizeId = product.size_id === null || product.size_id === undefined ? null : parseInt(String(product.size_id), 10);
                    const productUnitId = product.unit_id === null || product.unit_id === undefined ? null : parseInt(String(product.unit_id), 10);
                    
                    if (sizeId === productSizeId && unitId === productUnitId) {
                        // Match found on base product
                        unitPrice = Number(product.price);
                        // Label remains default or provided
                    } else {
                        return res.status(400).json({ 
                            success: false, 
                            message: `Variant with ${sizeId ? `size ${sizeId}` : ''} ${sizeId && unitId ? 'and ' : ''} ${unitId ? `unit ${unitId}` : ''} not found for product ${productId}` 
                        });
                    }
                }
            }

            preparedItems.push({ productId, quantity, unitPrice, sizeId, unitId, variantLabel, storeId: product.store_id });
            itemsSubtotal += unitPrice * quantity;
        }

        // Calculate delivery fee based on number of unique stores
        const storeCount = storeIds.size;
        let delivery_fee = 0;
        if (storeCount === 1) {
            delivery_fee = 70;
        } else if (storeCount === 2) {
            delivery_fee = 100;
        } else if (storeCount >= 3) {
            delivery_fee = 120 + (storeCount - 3) * 20;
        } else {
            delivery_fee = 70; // Fallback
        }

        const grandTotal = itemsSubtotal + delivery_fee;

        // Check Wallet
        let wallet = null;
        if (payment_method === 'wallet') {
            const [wallets] = await req.db.execute(
                'SELECT id, balance FROM wallets WHERE user_id = ?',
                [req.user.id]
            );

            if (!wallets.length) {
                return res.status(400).json({
                    success: false,
                    message: 'Wallet not found'
                });
            }

            wallet = wallets[0];
            const balance = parseFloat(wallet.balance);
            
            if (balance < grandTotal) {
                return res.status(400).json({
                    success: false,
                    message: `Insufficient wallet balance. Required: PKR ${grandTotal.toFixed(2)}, Available: PKR ${balance.toFixed(2)}`
                });
            }
        }

        // Create Single Order
        await ensureOrderItemsSchema(req.db);
        await ensureOrdersStoreIdNullable(req.db); // Ensure store_id can be NULL
        
        // Determine store_id for the order
        let orderStoreId = null;
        if (storeIds.size === 1) {
            orderStoreId = Array.from(storeIds)[0];
        }

        const [orderResult] = await req.db.execute(
            `INSERT INTO orders (order_number, user_id, store_id, total_amount, delivery_fee, payment_method, delivery_address, delivery_time, special_instructions)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [order_number, req.user.id, orderStoreId, grandTotal, delivery_fee, payment_method, delivery_address, delivery_time || null, special_instructions || null]
        );

        const orderId = orderResult.insertId;

        for (let item of preparedItems) {
            await req.db.execute(
                'INSERT INTO order_items (order_id, product_id, store_id, quantity, price, size_id, unit_id, variant_label) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
                [orderId, item.productId, item.storeId, item.quantity, item.unitPrice, item.sizeId, item.unitId, item.variantLabel]
            );
        }

        // Update Wallet
        if (payment_method === 'wallet' && wallet) {
            const newBalance = parseFloat(wallet.balance) - grandTotal;
            
            await req.db.execute(
                'UPDATE wallets SET balance = ?, total_spent = total_spent + ? WHERE id = ?',
                [newBalance, grandTotal, wallet.id]
            );
            
            await req.db.execute(
                `INSERT INTO wallet_transactions (wallet_id, type, amount, description, 
                 reference_type, reference_id, balance_after) VALUES (?, ?, ?, ?, ?, ?, ?)`,
                [wallet.id, 'debit', grandTotal, `Order payment - ${order_number}`, 
                 'order', orderId, newBalance]
            );
        }

        // Emit new_order event to admin
        try {
            const fs = require('fs');
            const path = require('path');
            const logEvent = (msg) => {
                try {
                    fs.appendFileSync(path.join(__dirname, '../socket_debug.log'), `[${new Date().toISOString()}] ${msg}\n`);
                } catch (e) {
                    console.error('Failed to write to socket_debug.log:', e);
                }
            };

            logEvent(`Order Created: ${order_number} (ID: ${orderId}). req.io present: ${!!req.io}`);
            if (req.io) {
                req.io.emit('new_order', {
                    id: orderId,
                    order_number: order_number,
                    total_amount: grandTotal,
                    store_id: orderStoreId,
                    created_at: new Date(),
                    user_id: req.user.id
                });
                logEvent(`new_order event emitted for ${order_number}. Total clients: ${req.io.engine.clientsCount}`);
            } else {
                logEvent(`WARNING: req.io missing for order ${order_number}`);
            }
        } catch (e) {
            console.error('Socket emit error:', e);
        }

        res.status(201).json({
            success: true,
            message: 'Order created successfully',
            order: {
                id: orderId,
                order_number: order_number,
                total_amount: grandTotal,
                store_id: orderStoreId
            }
        });

    } catch (error) {
        console.error('Error creating order:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to create order',
            error: error.message
        });
    }
});

// Get available riders
router.get('/available-riders', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const [riders] = await req.db.execute(
            'SELECT id, first_name, last_name, email, phone, vehicle_type FROM riders WHERE is_active = true ORDER BY first_name ASC'
        );

        res.json({
            success: true,
            riders
        });

    } catch (error) {
        console.error('Error fetching available riders:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch available riders',
            error: error.message
        });
    }
});

// Get rider's deliveries
router.get('/rider/deliveries', authenticateToken, async (req, res) => {
    try {
        await ensureOrderItemsSchema(req.db);
        if (req.user.user_type !== 'rider') {
            return res.status(403).json({
                success: false,
                message: 'Access denied. Rider only.'
            });
        }

        const { status } = req.query;
        let whereClause = 'o.rider_id = ?';
        if (status === 'assigned') {
            whereClause += " AND o.status IN ('out_for_delivery', 'confirmed', 'preparing', 'ready')";
        } else if (status === 'completed') {
            whereClause += " AND o.status = 'delivered'";
        }

        const [deliveries] = await req.db.execute(`
            SELECT o.*, u.first_name, u.last_name, u.phone, s.name as store_name, s.location as store_location
            FROM orders o
            JOIN users u ON o.user_id = u.id
            LEFT JOIN stores s ON o.store_id = s.id
            WHERE ${whereClause}
            ORDER BY o.created_at DESC
        `, [req.user.id]);

        // Fetch items for each delivery
        for (let delivery of deliveries) {
            // Set display name for multi-store orders
            if (!delivery.store_id) {
                delivery.store_name = 'Multiple Stores';
                delivery.store_location = 'Various Locations';
            }

            const [items] = await req.db.execute(`
                SELECT oi.*, p.name as product_name, p.image_url, s.name as store_name
                FROM order_items oi
                LEFT JOIN products p ON oi.product_id = p.id
                LEFT JOIN stores s ON oi.store_id = s.id
                WHERE oi.order_id = ?
            `, [delivery.id]);
            delivery.items = items;
        }

        res.json({
            success: true,
            deliveries
        });

    } catch (error) {
        console.error('Error fetching rider deliveries:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch deliveries',
            error: error.message
        });
    }
});

// Get rider profile
router.get('/rider/profile', authenticateToken, async (req, res) => {
    try {
        if (req.user.user_type !== 'rider') {
            return res.status(403).json({
                success: false,
                message: 'Access denied. Rider only.'
            });
        }

        const [riders] = await req.db.execute(
            'SELECT id, first_name, last_name, email, phone, vehicle_type, image_url, id_card_url FROM riders WHERE id = ?',
            [req.user.id]
        );

        if (riders.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'Rider not found'
            });
        }

        res.json({
            success: true,
            rider: riders[0]
        });

    } catch (error) {
        console.error('Error fetching rider profile:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch rider profile',
            error: error.message
        });
    }
});

// Update rider location
router.put('/rider/location', authenticateToken, [
    body('latitude').isFloat().withMessage('Invalid latitude'),
    body('longitude').isFloat().withMessage('Invalid longitude')
], async (req, res) => {
    try {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({
                success: false,
                message: 'Validation failed',
                errors: errors.array()
            });
        }

        if (req.user.user_type !== 'rider') {
            return res.status(403).json({
                success: false,
                message: 'Access denied. Rider only.'
            });
        }

        const { latitude, longitude } = req.body;
        const riderId = req.user.id;

        await ensureRiderLocationColumns(req.db);

        // Update rider location in database
        await req.db.execute(
            `UPDATE orders SET rider_latitude = ?, rider_longitude = ?
             WHERE rider_id = ? AND status = 'out_for_delivery'`,
            [latitude, longitude, riderId]
        );

        // Also store in a rider location log table if available
        try {
            await req.db.execute(
                `INSERT INTO rider_location_logs (rider_id, latitude, longitude) VALUES (?, ?, ?)`,
                [riderId, latitude, longitude]
            );
        } catch (e) {
            // Table might not exist yet, that's okay
        }

        res.json({
            success: true,
            message: 'Location updated successfully',
            location: { latitude, longitude }
        });

    } catch (error) {
        console.error('Error updating rider location:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update location',
            error: error.message
        });
    }
});

// Get single order details
router.get('/:id(\\d+)', authenticateToken, async (req, res) => {
    console.log(`[orders] Fetching order details for ID: ${req.params.id}`);
    try {
        const { id } = req.params;
        await ensureOrderItemsSchema(req.db);

        const [orders] = await req.db.execute(`
            SELECT o.*, u.first_name, u.last_name, u.email, u.phone, s.name as store_name,
                   r.first_name as rider_first_name, r.last_name as rider_last_name, r.phone as rider_phone
            FROM orders o
            JOIN users u ON o.user_id = u.id
            LEFT JOIN stores s ON o.store_id = s.id
            LEFT JOIN riders r ON o.rider_id = r.id
            WHERE o.id = ?
        `, [id]);

        console.log(`[orders] Found ${orders.length} orders for ID: ${id}`);

        if (orders.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'Order not found'
            });
        }

        const order = orders[0];

        // Check permission: Admin, Rider assigned, or Customer who owns the order
        if (req.user.user_type !== 'admin' && 
            req.user.id !== order.user_id && 
            (req.user.user_type === 'rider' && req.user.id !== order.rider_id)) {
            return res.status(403).json({
                success: false,
                message: 'Access denied'
            });
        }

        // Get order items with store info
        const [items] = await req.db.execute(`
            SELECT oi.*, p.name as product_name, p.image_url, s.name as store_name
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            LEFT JOIN stores s ON oi.store_id = s.id
            WHERE oi.order_id = ?
        `, [id]);
        
        order.items = items;

        // Group items by store for proper multi-store display
        const storeGroups = {};
        items.forEach(item => {
            const sId = item.store_id || 'unknown';
            if (!storeGroups[sId]) {
                storeGroups[sId] = {
                    store_id: item.store_id,
                    store_name: item.store_name || 'Unknown Store',
                    items: []
                };
            }
            storeGroups[sId].items.push(item);
        });
        
        order.store_wise_items = Object.values(storeGroups);

        res.json({
            success: true,
            order
        });

    } catch (error) {
        console.error('Error fetching order details:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch order details',
            error: error.message
        });
    }
});

// Get all orders (Admin only)
router.get('/', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { status } = req.query;
        let whereClause = '';
        if (status && status !== 'all') {
            whereClause = `WHERE o.status = '${status}'`;
        }

        const [orders] = await req.db.execute(`
            SELECT o.*, u.first_name, u.last_name, u.email, s.name as store_name,
                   r.first_name as rider_first_name, r.last_name as rider_last_name,
                   CAST((SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS SIGNED) as items_count
            FROM orders o
            JOIN users u ON o.user_id = u.id
            LEFT JOIN stores s ON o.store_id = s.id
            LEFT JOIN riders r ON o.rider_id = r.id
            ${whereClause}
            ORDER BY o.created_at DESC
        `);

        res.json({
            success: true,
            orders
        });

    } catch (error) {
        console.error('Error fetching orders:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch orders',
            error: error.message
        });
    }
});

// Update order status (Admin or Store Owner)
router.put('/:id(\\d+)/status', authenticateToken, requireStoreOwner, [
    body('status').isIn(['pending', 'confirmed', 'preparing', 'ready', 'delivered', 'cancelled']).withMessage('Invalid status')
], async (req, res) => {
    try {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({
                success: false,
                message: 'Validation failed',
                errors: errors.array()
            });
        }

        const { id } = req.params;
        const { status } = req.body;

        // Check if order exists and user has permission
        const [orders] = await req.db.execute(`
            SELECT o.*, s.owner_id
            FROM orders o
            LEFT JOIN stores s ON o.store_id = s.id
            WHERE o.id = ?
        `, [id]);

        if (orders.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'Order not found'
            });
        }

        const order = orders[0];

        // Check ownership permission
        if (req.user.user_type !== 'admin' && (!order.owner_id || order.owner_id !== req.user.id)) {
            return res.status(403).json({
                success: false,
                message: 'You do not have permission to update this order'
            });
        }

        await req.db.execute(
            'UPDATE orders SET status = ? WHERE id = ?',
            [status, id]
        );

        // Emit order_status_update event
        try {
            if (req.io) {
                req.io.emit('order_status_update', {
                    id: id,
                    order_number: order.order_number,
                    status: status,
                    updated_at: new Date()
                });
                const fs = require('fs');
                const path = require('path');
                const logMsg = `[${new Date().toISOString()}] Status updated: ${order.order_number} -> ${status}. Total clients: ${req.io.engine.clientsCount}\n`;
                fs.appendFileSync(path.join(__dirname, '../socket_debug.log'), logMsg);
            }
        } catch (e) {
            console.error('Socket emit error:', e);
        }

        res.json({
            success: true,
            message: 'Order status updated successfully'
        });

    } catch (error) {
        console.error('Error updating order:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update order',
            error: error.message
        });
    }
});

// Assign rider to order (Admin only)
router.put('/:id(\\d+)/assign-rider', authenticateToken, requireAdmin, [
    body('rider_id').isInt().withMessage('Rider ID must be a valid integer'),
    body('delivery_fee').optional().isFloat({ min: 0 }).withMessage('Invalid delivery fee')
], async (req, res) => {
    try {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({
                success: false,
                message: 'Validation failed',
                errors: errors.array()
            });
        }

        const { id } = req.params;
        const { rider_id, delivery_fee } = req.body;

        // Check if order exists
        const [orders] = await req.db.execute('SELECT id, order_number, total_amount, delivery_fee, status FROM orders WHERE id = ?', [id]);
        if (orders.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'Order not found'
            });
        }

        const order = orders[0];

        // Do not allow assigning riders to already completed or cancelled orders
        if (order.status === 'delivered' || order.status === 'cancelled') {
            return res.status(400).json({
                success: false,
                message: `Cannot assign rider to an order that is already ${order.status}`
            });
        }

        // Check if rider exists and is available
        const [riders] = await req.db.execute(
            'SELECT id, first_name, last_name FROM riders WHERE id = ? AND is_active = true',
            [rider_id]
        );
        if (riders.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'Rider not found or not active'
            });
        }

        const rider = riders[0];

        // Set estimated delivery time (current time + 30 minutes)
        const estimatedDelivery = new Date(Date.now() + 30 * 60 * 1000);

        // Recalculate total if delivery fee is updated
        let newTotal = order.total_amount;
        let finalDeliveryFee = order.delivery_fee;

        if (delivery_fee !== undefined) {
            finalDeliveryFee = parseFloat(delivery_fee);
            const itemsSubtotal = order.total_amount - order.delivery_fee;
            newTotal = itemsSubtotal + finalDeliveryFee;
        }

        // Assign rider and update status
        await req.db.execute(
            'UPDATE orders SET rider_id = ?, status = ?, estimated_delivery_time = ?, delivery_fee = ?, total_amount = ? WHERE id = ?',
            [rider_id, 'out_for_delivery', estimatedDelivery, finalDeliveryFee, newTotal, id]
        );

        // Emit order_assigned event
        try {
            if (req.io) {
                req.io.emit('order_assigned', {
                    id: id,
                    order_number: order.order_number,
                    rider_id: rider_id,
                    rider_name: `${rider.first_name} ${rider.last_name}`,
                    status: 'out_for_delivery',
                    estimated_delivery_time: estimatedDelivery,
                    delivery_fee: finalDeliveryFee,
                    total_amount: newTotal
                });
                const fs = require('fs');
                const path = require('path');
                const logMsg = `[${new Date().toISOString()}] Order assigned: ${order.order_number} to ${rider.first_name}. Fee: ${finalDeliveryFee}, Total: ${newTotal}\n`;
                fs.appendFileSync(path.join(__dirname, '../socket_debug.log'), logMsg);
            }
        } catch (e) {
            console.error('Socket emit error:', e);
        }

        res.json({
            success: true,
            message: 'Rider assigned successfully',
            delivery_fee: finalDeliveryFee,
            total_amount: newTotal
        });

    } catch (error) {
        console.error('Error assigning rider:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to assign rider',
            error: error.message
        });
    }
});

// Update rider location (Rider or Admin)
router.put('/:id(\\d+)/rider-location', authenticateToken, [
    body('latitude').optional().isFloat().withMessage('Invalid latitude'),
    body('longitude').optional().isFloat().withMessage('Invalid longitude'),
    body('location').optional().notEmpty().withMessage('Location is required')
], async (req, res) => {
    try {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({
                success: false,
                message: 'Validation failed',
                errors: errors.array()
            });
        }

        const { id } = req.params;
        const { location, latitude, longitude } = req.body;

        // Check if order exists and user has permission (rider or admin)
        const [orders] = await req.db.execute(
            'SELECT rider_id FROM orders WHERE id = ?',
            [id]
        );

        if (orders.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'Order not found'
            });
        }

        const order = orders[0];

        // Check ownership permission
        if (req.user.user_type !== 'admin' && order.rider_id !== req.user.id) {
            return res.status(403).json({
                success: false,
                message: 'You do not have permission to update this order'
            });
        }

        await ensureRiderLocationColumns(req.db);

        if (latitude !== undefined && longitude !== undefined) {
            await req.db.execute(
                'UPDATE orders SET rider_latitude = ?, rider_longitude = ? WHERE id = ?',
                [latitude, longitude, id]
            );
        }

        res.json({
            success: true,
            message: 'Rider location updated successfully'
        });

    } catch (error) {
        console.error('Error updating rider location:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update rider location',
            error: error.message
        });
    }
});

// Mark order as delivered (Rider or Admin)
router.put('/:id(\\d+)/deliver', authenticateToken, async (req, res) => {
    try {
        const { id } = req.params;

        // Check if order exists and user has permission (rider or admin)
        const [orders] = await req.db.execute(
            'SELECT rider_id FROM orders WHERE id = ?',
            [id]
        );

        if (orders.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'Order not found'
            });
        }

        const order = orders[0];

        // Check ownership permission
        if (req.user.user_type !== 'admin' && order.rider_id !== req.user.id) {
            return res.status(403).json({
                success: false,
                message: 'You do not have permission to update this order'
            });
        }

        await req.db.execute(
            'UPDATE orders SET status = ? WHERE id = ?',
            ['delivered', id]
        );

        res.json({
            success: true,
            message: 'Order marked as delivered successfully'
        });

    } catch (error) {
        console.error('Error marking order as delivered:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to mark order as delivered',
            error: error.message
        });
    }
});

// Update payment status (Admin or Rider)
router.put('/:id(\\d+)/payment-status', authenticateToken, [
    body('payment_status').isIn(['pending', 'paid', 'failed']).withMessage('Invalid payment status')
], async (req, res) => {
    try {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({
                success: false,
                message: 'Validation failed',
                errors: errors.array()
            });
        }

        const { id } = req.params;
        const { payment_status } = req.body;

        if (!payment_status) {
            return res.status(400).json({
                success: false,
                message: 'Payment status is required'
            });
        }

        // Check if order exists and user has permission (rider or admin)
        const [orders] = await req.db.execute(
            'SELECT rider_id, total_amount, payment_status FROM orders WHERE id = ?',
            [id]
        );

        if (orders.length === 0) {
            return res.status(404).json({
                success: false,
                message: 'Order not found'
            });
        }

        const order = orders[0];

        // Check ownership permission
        if (req.user.user_type !== 'admin' && order.rider_id !== req.user.id) {
            return res.status(403).json({
                success: false,
                message: 'You do not have permission to update this order'
            });
        }

        await req.db.execute(
            'UPDATE orders SET payment_status = ? WHERE id = ?',
            [payment_status, id]
        );

        if (payment_status === 'paid' && order.rider_id && order.payment_status !== 'paid') {
            const [wallets] = await req.db.execute(
                'SELECT id, balance FROM wallets WHERE rider_id = ?',
                [order.rider_id]
            );

            if (wallets.length > 0) {
                const wallet = wallets[0];
                const newBalance = parseFloat(wallet.balance || 0) + parseFloat(order.total_amount || 0);
                
                await req.db.execute(
                    'UPDATE wallets SET balance = ?, total_credited = total_credited + ? WHERE id = ?',
                    [newBalance, order.total_amount, wallet.id]
                );

                await req.db.execute(
                    `INSERT INTO wallet_transactions (wallet_id, type, amount, description, reference_type, reference_id, balance_after) 
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    [wallet.id, 'credit', order.total_amount, `Payment received for order #${id}`, 'order', id, newBalance]
                );
            } else {
                await req.db.execute(
                    'INSERT INTO wallets (rider_id, user_type, balance, total_credited) VALUES (?, ?, ?, ?)',
                    [order.rider_id, 'rider', order.total_amount, order.total_amount]
                );

                const [newWallets] = await req.db.execute(
                    'SELECT id FROM wallets WHERE rider_id = ?',
                    [order.rider_id]
                );

                if (newWallets.length > 0) {
                    await req.db.execute(
                        `INSERT INTO wallet_transactions (wallet_id, type, amount, description, reference_type, reference_id, balance_after) 
                         VALUES (?, ?, ?, ?, ?, ?, ?)`,
                        [newWallets[0].id, 'credit', order.total_amount, `Payment received for order #${id}`, 'order', id, order.total_amount]
                    );
                }
            }
        }

        res.json({
            success: true,
            message: 'Payment status updated successfully'
        });

    } catch (error) {
        console.error('Error updating payment status:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update payment status',
            error: error.message
        });
    }
});

module.exports = router;
