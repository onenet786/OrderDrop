const express = require("express");
const { body, validationResult } = require("express-validator");
const {
  authenticateToken,
  requireAdmin,
  requireStoreOwner,
  requireDispatchAccess,
  requireStaffAccess,
} = require("../middleware/auth");
const { sendOrderThanksEmail } = require("../services/emailService");
const { recordFinancialTransaction } = require("../utils/dbHelpers");

const router = express.Router();

async function hasColumn(db, table, column) {
  const [rows] = await db.execute(
    "SELECT COUNT(*) AS cnt FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
    [table, column],
  );
  return rows && rows[0] && rows[0].cnt > 0;
}

async function ensureOrderItemsSchema(db) {
  const columns = [
    { name: "size_id", definition: "INT NULL" },
    { name: "unit_id", definition: "INT NULL" },
    { name: "variant_label", definition: "VARCHAR(255) NULL" },
    {
      name: "store_id",
      definition: "INT NULL",
      constraint:
        "FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE SET NULL",
    },
    { name: "discount_type", definition: "ENUM('amount', 'percent') NULL" },
    { name: "discount_value", definition: "DECIMAL(10, 2) NULL" },
    {
      name: "item_status",
      definition:
        "ENUM('pending', 'confirmed', 'preparing', 'ready', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled') DEFAULT 'pending'",
    },
  ];

  for (const col of columns) {
    try {
      const exists = await hasColumn(db, "order_items", col.name);
      if (!exists) {
        await db.execute(
          `ALTER TABLE order_items ADD COLUMN ${col.name} ${col.definition}`,
        );
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
  try {
    await db.execute(
      "ALTER TABLE order_items MODIFY COLUMN item_status ENUM('pending','confirmed','preparing','ready','ready_for_pickup','picked_up','out_for_delivery','delivered','cancelled') DEFAULT 'pending'"
    );
  } catch (_) {}
}

async function ensureOrdersParentColumn(db) {
  try {
    // Try to select the column to check existence (more robust than information_schema)
    await db.execute("SELECT parent_order_number FROM orders LIMIT 1");
  } catch (e) {
    // If error is about missing column, add it
    if (
      e.code === "ER_BAD_FIELD_ERROR" ||
      (e.message && e.message.includes("Unknown column"))
    ) {
      try {
        await db.execute(
          "ALTER TABLE orders ADD COLUMN parent_order_number VARCHAR(50) NULL",
        );
        try {
          await db.execute(
            "CREATE INDEX idx_orders_parent_order_number ON orders(parent_order_number)",
          );
        } catch (idxErr) {
          // Ignore index creation error
        }
      } catch (alterErr) {
        console.error("Failed to add parent_order_number column:", alterErr);
      }
    }
  }
}

async function ensureOrdersStoreIdNullable(db) {
  try {
    // Check if store_id is nullable (simplified: just try to modify it)
    await db.execute("ALTER TABLE orders MODIFY COLUMN store_id INT NULL");
  } catch (e) {
    // Ignore if already nullable or other non-critical errors
    // console.error('Failed to make store_id nullable:', e);
  }
}

async function ensureRiderLocationColumns(db) {
  try {
    const hasRiderLatitude = await hasColumn(db, "orders", "rider_latitude");
    if (!hasRiderLatitude) {
      await db.execute(
        "ALTER TABLE orders ADD COLUMN rider_latitude DECIMAL(10, 8) NULL",
      );
    }
  } catch (e) {
    console.error("Failed to add rider_latitude column:", e);
  }

  try {
    const hasRiderLongitude = await hasColumn(db, "orders", "rider_longitude");
    if (!hasRiderLongitude) {
      await db.execute(
        "ALTER TABLE orders ADD COLUMN rider_longitude DECIMAL(11, 8) NULL",
      );
    }
  } catch (e) {
    console.error("Failed to add rider_longitude column:", e);
  }
}

// Get user's orders
router.get("/my-orders", authenticateToken, async (req, res) => {
  try {
    await ensureOrderItemsSchema(req.db);

    const { status } = req.query;
    let query = `
            SELECT o.*, s.name as store_name, s.location as store_location,
                   r.first_name as rider_first_name, r.last_name as rider_last_name, r.phone as rider_phone
            FROM orders o
            LEFT JOIN stores s ON o.store_id = s.id
            LEFT JOIN riders r ON o.rider_id = r.id
            WHERE o.user_id = ?
        `;
    const params = [req.user.id];

    if (status && status !== "all") {
      if (status === "pending") {
        query +=
          " AND o.status IN ('pending', 'confirmed', 'preparing', 'ready', 'out_for_delivery')";
      } else {
        query += " AND o.status = ?";
        params.push(status);
      }
    }

    query += " ORDER BY o.created_at DESC";

    const [orders] = await req.db.execute(query, params);

    // Get order items for each order
    for (let order of orders) {
      // Check if product_variants table exists before querying
      let hasVariantsTable = false;
      try {
        await req.db.execute("SELECT 1 FROM product_variants LIMIT 1");
        hasVariantsTable = true;
      } catch (e) {
        // Table doesn't exist
      }

      let itemsQuery;
      if (hasVariantsTable) {
        itemsQuery = `
                SELECT oi.*, p.name as product_name, p.image_url, p.store_id, s.name as item_store_name,
                       v.label as variant_label
                FROM order_items oi
                JOIN products p ON oi.product_id = p.id
                LEFT JOIN product_variants v ON oi.variant_id = v.id
                LEFT JOIN stores s ON oi.store_id = s.id
                WHERE oi.order_id = ?
            `;
      } else {
         itemsQuery = `
                SELECT oi.*, p.name as product_name, p.image_url, p.store_id, s.name as item_store_name,
                       NULL as variant_label
                FROM order_items oi
                JOIN products p ON oi.product_id = p.id
                LEFT JOIN stores s ON oi.store_id = s.id
                WHERE oi.order_id = ?
            `;
      }

      const [items] = await req.db.execute(itemsQuery, [order.id]);
      order.items = items;

      // If store_id is NULL (multi-store order), set display name
      // Note: In some schemas, store_id might be 0 or null.
      if (!order.store_id) {
        order.store_name = "Multiple Stores";
        order.is_group = true; // reusing existing frontend logic

        // Group items by store for display if needed, or just let frontend handle it
        // We can construct sub_orders mock structure for frontend compatibility
        const storeGroups = {};
        items.forEach((item) => {
          // If store_id is null/undefined in item, fallback to something safe
          const sId = item.store_id || 'unknown';
          
          if (!storeGroups[sId]) {
            storeGroups[sId] = {
              store_id: sId,
              store_name: item.item_store_name || 'Unknown Store',
              status: item.item_status || 'pending', // Use item-specific status!
              items: [],
              rider_first_name: order.rider_first_name,
              rider_last_name: order.rider_last_name,
              rider_phone: order.rider_phone
            };
          }
          storeGroups[sId].items.push(item);
        });
        order.sub_orders = Object.values(storeGroups);
      }
    }

    res.json({
      success: true,
      orders: orders,
    });
  } catch (error) {
    console.error("Error fetching orders:", error);
    res.status(500).json({
      success: false,
      message: "Failed to fetch orders",
      error: error.message,
    });
  }
});

// Test notification endpoint
router.get("/test-notification", (req, res) => {
  try {
    const fs = require("fs");
    const path = require("path");
    const logEvent = (msg) => {
      fs.appendFile(
        path.join(__dirname, "../socket_debug.log"),
        `[${new Date().toISOString()}] ${msg}\n`,
        () => {},
      );
    };

    logEvent(
      `Attempting to emit TEST notification. req.io present: ${!!req.io}`,
    );
    if (req.io) {
      req.io.to("admins").emit("new_order", {
        id: 0,
        order_number: "TEST-SOCKET",
        total_amount: 0.0,
        created_at: new Date(),
      });
      logEvent("TEST notification emitted");
      return res.json({ success: true, message: "Test notification emitted" });
    }
    logEvent("ERROR: req.io not found for TEST notification");
    res.status(500).json({ success: false, message: "req.io not found" });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// Create new order
router.post("/", authenticateToken, async (req, res) => {
  try {
    const {
      items,
      delivery_address,
      delivery_time,
      payment_method,
      special_instructions,
    } = req.body;

    if (!items || items.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Order must contain at least one item",
      });
    }

    if (!delivery_address || delivery_address.trim() === "") {
      return res.status(400).json({
        success: false,
        message: "Delivery address is required",
      });
    }

    if (!payment_method) {
      return res.status(400).json({
        success: false,
        message: "Payment method is required",
      });
    }

    // Generate Order Number: Ordyymmddxxxx
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, "0");
    const dd = String(now.getDate()).padStart(2, "0");
    const datePart = `${yy}${mm}${dd}`;
    const prefix = `Ord${datePart}`;

    const [rows] = await req.db.execute(
      "SELECT order_number FROM orders WHERE order_number LIKE ? ORDER BY order_number DESC LIMIT 1",
      [`${prefix}%`],
    );

    let sequence = 1;
    if (rows && rows.length > 0) {
      const lastOrderNumber = rows[0].order_number;
      const lastSequenceStr = lastOrderNumber.slice(-4);
      if (/^\d{4}$/.test(lastSequenceStr)) {
        sequence = parseInt(lastSequenceStr, 10) + 1;
      }
    }

    const order_number = `${prefix}${String(sequence).padStart(4, "0")}`;

    // Validate and prepare items
    const preparedItems = [];
    const storeIds = new Set();
    let itemsSubtotal = 0;

    for (let item of items) {
      const productId = parseInt(String(item.product_id), 10);
      const quantity = parseInt(String(item.quantity), 10);
      const sizeId =
        item.size_id === null || item.size_id === undefined
          ? null
          : parseInt(String(item.size_id), 10);
      const unitId =
        item.unit_id === null || item.unit_id === undefined
          ? null
          : parseInt(String(item.unit_id), 10);
      const providedVariantLabel = item.variant_label
        ? String(item.variant_label)
        : null;

      if (
        !Number.isInteger(productId) ||
        productId <= 0 ||
        !Number.isInteger(quantity) ||
        quantity <= 0
      ) {
        return res
          .status(400)
          .json({ success: false, message: "Invalid order item payload" });
      }

      const [products] = await req.db.execute(
        "SELECT id, price, store_id, name, size_id, unit_id, discount_type, discount_value FROM products WHERE id = ? AND is_available = true",
        [productId],
      );

      if (!products || products.length === 0) {
        return res.status(400).json({
          success: false,
          message: `Product ${productId} not found or not available`,
        });
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
            const sizeLabel = rows[0].size_label
              ? String(rows[0].size_label)
              : "";
            const unitLabel =
              rows[0].unit_abbreviation || rows[0].unit_name
                ? String(rows[0].unit_abbreviation || rows[0].unit_name)
                : "";
            variantLabel =
              sizeLabel && unitLabel
                ? `${sizeLabel} ${unitLabel}`
                : sizeLabel || unitLabel || null;
          }
        } else {
          // Fallback: Check if requested variant matches the base product's size/unit
          const productSizeId =
            product.size_id === null || product.size_id === undefined
              ? null
              : parseInt(String(product.size_id), 10);
          const productUnitId =
            product.unit_id === null || product.unit_id === undefined
              ? null
              : parseInt(String(product.unit_id), 10);

          if (sizeId === productSizeId && unitId === productUnitId) {
            // Match found on base product
            unitPrice = Number(product.price);
            // Label remains default or provided
          } else {
            return res.status(400).json({
              success: false,
              message: `Variant with ${sizeId ? `size ${sizeId}` : ""} ${sizeId && unitId ? "and " : ""} ${unitId ? `unit ${unitId}` : ""} not found for product ${productId}`,
            });
          }
        }
      }

      // Calculate discounted price for subtotal calculation
      let finalUnitPrice = unitPrice;
      const discountType = product.discount_type;
      const discountValue = product.discount_value
        ? Number(product.discount_value)
        : 0;

      if (discountType && Number.isFinite(discountValue) && discountValue > 0) {
        if (discountType === "percent") {
          finalUnitPrice = unitPrice * (1 - discountValue / 100);
        } else if (discountType === "amount") {
          finalUnitPrice = unitPrice - discountValue;
        }

        // Ensure price doesn't go below 0
        if (finalUnitPrice < 0) finalUnitPrice = 0;

        // Round to 2 decimal places
        finalUnitPrice = Math.round(finalUnitPrice * 100) / 100;
      }

      preparedItems.push({
        productId,
        quantity,
        unitPrice,
        sizeId,
        unitId,
        variantLabel,
        storeId: product.store_id,
        discount_type: product.discount_type,
        discount_value: product.discount_value,
      });
      // Use finalUnitPrice (discounted) for the total calculation
      itemsSubtotal += finalUnitPrice * quantity;
    }

    // Enforce store open/closed hours before proceeding
    const storeIdArray = Array.from(storeIds).filter(Boolean);
    if (storeIdArray.length > 0) {
      const placeholders = storeIdArray.map(() => "?").join(",");
      const [storeRows] = await req.db.execute(
        `SELECT id, name, opening_time, closing_time, is_active FROM stores WHERE id IN (${placeholders})`,
        storeIdArray,
      );

      const now = new Date();
      const nowDouble = now.getHours() + now.getMinutes() / 60.0;
      const parseTimeStr = (t) => {
        if (!t) return null;
        const parts = String(t).split(":");
        const h = parseInt(parts[0], 10);
        const m = parseInt(parts[1], 10);
        if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
        return h + m / 60.0;
      };

      for (const s of storeRows) {
        if (!s.is_active) {
          return res.status(400).json({
            success: false,
            message: `Store "${s.name}" is not active at the moment. Please try later.`,
          });
        }
        const openD = parseTimeStr(s.opening_time);
        const closeD = parseTimeStr(s.closing_time);
        if (openD === null || closeD === null) {
          return res.status(400).json({
            success: false,
            message: `Store "${s.name}" is currently closed.`,
          });
        }
        let isOpen;
        if (openD <= closeD) {
          isOpen = nowDouble >= openD && nowDouble <= closeD;
        } else {
          // Overnight hours (e.g., 22:00 - 04:00)
          isOpen = nowDouble >= openD || nowDouble <= closeD;
        }
        if (!isOpen) {
          return res.status(400).json({
            success: false,
            message: `Store "${s.name}" is currently closed. Please order during open hours.`,
          });
        }
      }
    }

    // Calculate delivery fee based on number of unique stores
    const storeCount = storeIds.size;
    let delivery_fee = 0;
    if (storeCount === 1) {
      delivery_fee = 70;
    } else if (storeCount === 2) {
      delivery_fee = 100;
    } else if (storeCount >= 3) {
      delivery_fee = 130 + (storeCount - 3) * 30;
    } else {
      delivery_fee = 70; // Fallback
    }

    const grandTotal = itemsSubtotal + delivery_fee;

    // Check Wallet
    let wallet = null;
    if (payment_method === "wallet") {
      const [wallets] = await req.db.execute(
        "SELECT id, balance FROM wallets WHERE user_id = ?",
        [req.user.id],
      );

      if (!wallets.length) {
        return res.status(400).json({
          success: false,
          message: "Wallet not found",
        });
      }

      wallet = wallets[0];
      const balance = parseFloat(wallet.balance);

      if (balance < grandTotal) {
        return res.status(400).json({
          success: false,
          message: `Insufficient wallet balance. Required: PKR ${grandTotal.toFixed(2)}, Available: PKR ${balance.toFixed(2)}`,
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
      [
        order_number,
        req.user.id,
        orderStoreId,
        grandTotal,
        delivery_fee,
        payment_method,
        delivery_address,
        delivery_time || null,
        special_instructions || null,
      ],
    );

    const orderId = orderResult.insertId;

    for (let item of preparedItems) {
      await req.db.execute(
        "INSERT INTO order_items (order_id, product_id, store_id, quantity, price, size_id, unit_id, variant_label, discount_type, discount_value) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          orderId,
          item.productId,
          item.storeId,
          item.quantity,
          item.unitPrice,
          item.sizeId,
          item.unitId,
          item.variantLabel,
          item.discount_type || null,
          item.discount_value || null,
        ],
      );
    }

    // Update Wallet
    if (payment_method === "wallet" && wallet) {
      const newBalance = parseFloat(wallet.balance) - grandTotal;

      await req.db.execute(
        "UPDATE wallets SET balance = ?, total_spent = total_spent + ? WHERE id = ?",
        [newBalance, grandTotal, wallet.id],
      );

      await req.db.execute(
        `INSERT INTO wallet_transactions (wallet_id, type, amount, description, 
                 reference_type, reference_id, balance_after) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          wallet.id,
          "debit",
          grandTotal,
          `Order payment - ${order_number}`,
          "order",
          orderId,
          newBalance,
        ],
      );
    }

    // Emit new_order event to admin
    try {
      const fs = require("fs");
      const path = require("path");
      const logEvent = (msg) => {
        fs.appendFile(
          path.join(__dirname, "../socket_debug.log"),
          `[${new Date().toISOString()}] ${msg}\n`,
          (e) => {
            if (e) console.error("Failed to write to socket_debug.log:", e);
          },
        );
      };

      logEvent(
        `Order Created: ${order_number} (ID: ${orderId}). req.io present: ${!!req.io}`,
      );
      if (req.io) {
        req.io.to("admins").emit("new_order", {
          id: orderId,
          order_number: order_number,
          total_amount: grandTotal,
          store_id: orderStoreId,
          created_at: new Date(),
          user_id: req.user.id,
        });
        logEvent(
          `new_order event emitted for ${order_number}. Total clients: ${req.io.engine.clientsCount}`,
        );

        // Notify Store Owners
        const storeIdList = Array.from(storeIds);
        if (storeIdList.length > 0) {
          const placeholders = storeIdList.map(() => "?").join(",");
          const [stores] = await req.db.execute(
            `SELECT id, owner_id, name FROM stores WHERE id IN (${placeholders})`,
            storeIdList,
          );

          for (const store of stores) {
            if (store.owner_id) {
              req.io
                .to(`user_${store.owner_id}`)
                .emit("store_owner_notification", {
                  type: "new_order",
                  order_id: orderId,
                  order_number: order_number,
                  store_id: store.id,
                  store_name: store.name,
                  message: `New order ${order_number} for ${store.name}`,
                  timestamp: new Date(),
                });
              logEvent(
                `store_owner_notification emitted to user_${store.owner_id}`,
              );
            }
          }
        }
      } else {
        logEvent(`WARNING: req.io missing for order ${order_number}`);
      }
    } catch (e) {
      console.error("Socket emit error:", e);
    }

    res.status(201).json({
      success: true,
      message: "Order created successfully",
      order: {
        id: orderId,
        order_number: order_number,
        total_amount: grandTotal,
        store_id: orderStoreId,
      },
    });
  } catch (error) {
    console.error("Error creating order:", error);
    res.status(500).json({
      success: false,
      message: "Failed to create order",
      error: error.message,
    });
  }
});

// Get available riders (Admin & Dispatch)
router.get(
  "/available-riders",
  authenticateToken,
  requireDispatchAccess,
  async (req, res) => {
    try {
      const [riders] = await req.db.execute(
        "SELECT id, first_name, last_name, email, phone, vehicle_type FROM riders WHERE is_active = true AND is_available = true ORDER BY first_name ASC LIMIT 500",
      );

      res.json({
        success: true,
        riders: riders || [],
      });
    } catch (error) {
      console.error("Error fetching available riders:", error);
      res.status(500).json({
        success: false,
        message: "Failed to fetch available riders",
        error: error.message,
      });
    }
  },
);

// Get current rider's deliveries (for mobile app)
router.get("/rider/deliveries", authenticateToken, async (req, res) => {
  try {
    await ensureOrderItemsSchema(req.db);
    if (req.user.user_type !== "rider") {
      return res.status(403).json({
        success: false,
        message: "Access denied. Rider only.",
      });
    }

    const riderId = req.user.id;

    // Check if rider exists and is active
    const [riders] = await req.db.execute(
      "SELECT id FROM riders WHERE id = ? AND is_active = true",
      [riderId],
    );

    if (riders.length === 0) {
      return res.status(403).json({
        success: false,
        message: "Rider account is inactive or not found. Access denied.",
      });
    }

    const { status } = req.query;
    let whereClause = "o.rider_id = ?";
    if (status === "assigned") {
      whereClause +=
        " AND o.status IN ('out_for_delivery', 'confirmed', 'preparing', 'ready')";
    } else if (status === "completed") {
      whereClause += " AND o.status = 'delivered'";
    }

    const [deliveries] = await req.db.execute(
      `
            SELECT o.*, u.first_name, u.last_name, u.phone, s.name as store_name, s.location as store_location
            FROM orders o
            JOIN users u ON o.user_id = u.id
            LEFT JOIN stores s ON o.store_id = s.id
            WHERE ${whereClause}
            ORDER BY o.created_at DESC
        `,
      [riderId],
    );

    // Fetch items for each delivery
    for (let delivery of deliveries) {
      // Set display name for multi-store orders
      if (!delivery.store_id) {
        delivery.store_name = "Multiple Stores";
        delivery.store_location = "Various Locations";
      }

      const [items] = await req.db.execute(
        `
                SELECT oi.*, p.name as product_name, p.image_url, s.name as store_name
                FROM order_items oi
                LEFT JOIN products p ON oi.product_id = p.id
                LEFT JOIN stores s ON oi.store_id = s.id
                WHERE oi.order_id = ?
            `,
        [delivery.id],
      );
      delivery.items = items;
    }

    res.json({
      success: true,
      deliveries,
    });
  } catch (error) {
    console.error("Error fetching rider deliveries:", error);
    res.status(500).json({
      success: false,
      message: "Failed to fetch deliveries",
      error: error.message,
    });
  }
});

// Get rider's deliveries by ID (for admins viewing a specific rider)
router.get(
  "/rider/:riderId/deliveries",
  authenticateToken,
  async (req, res) => {
    try {
      await ensureOrderItemsSchema(req.db);
      const { riderId } = req.params;
      const { status } = req.query;

      // Only riders can view their own deliveries, admins can view any rider's deliveries
      if (req.user.user_type === "rider" && req.user.id != riderId) {
        return res.status(403).json({
          success: false,
          message: "Access denied. You can only view your own deliveries.",
        });
      }
      if (
        req.user.user_type !== "rider" &&
        req.user.user_type !== "admin" &&
        req.user.user_type !== "standard_user"
      ) {
        return res.status(403).json({
          success: false,
          message: "Access denied.",
        });
      }

      let whereClause = "o.rider_id = ?";
      if (status === "assigned") {
        whereClause +=
          " AND o.status IN ('out_for_delivery', 'confirmed', 'preparing', 'ready')";
      } else if (status === "completed") {
        whereClause += " AND o.status = 'delivered'";
      }

      const [deliveries] = await req.db.execute(
        `
            SELECT o.*, u.first_name, u.last_name, u.phone, s.name as store_name, s.location as store_location
            FROM orders o
            JOIN users u ON o.user_id = u.id
            LEFT JOIN stores s ON o.store_id = s.id
            WHERE ${whereClause}
            ORDER BY o.created_at DESC
        `,
        [riderId],
      );

      // Fetch items for each delivery
      for (let delivery of deliveries) {
        // Set display name for multi-store orders
        if (!delivery.store_id) {
          delivery.store_name = "Multiple Stores";
          delivery.store_location = "Various Locations";
        }

        const [items] = await req.db.execute(
          `
                SELECT oi.*, p.name as product_name, p.image_url, s.name as store_name
                FROM order_items oi
                LEFT JOIN products p ON oi.product_id = p.id
                LEFT JOIN stores s ON oi.store_id = s.id
                WHERE oi.order_id = ?
            `,
          [delivery.id],
        );
        delivery.items = items;
      }

      res.json({
        success: true,
        deliveries,
      });
    } catch (error) {
      console.error("Error fetching rider deliveries:", error);
      res.status(500).json({
        success: false,
        message: "Failed to fetch deliveries",
        error: error.message,
      });
    }
  },
);

// Get rider profile
router.get("/rider/profile", authenticateToken, async (req, res) => {
  try {
    if (req.user.user_type !== "rider") {
      return res.status(403).json({
        success: false,
        message: "Access denied. Rider only.",
      });
    }

    const [riders] = await req.db.execute(
      "SELECT id, first_name, last_name, email, phone, vehicle_type, image_url, id_card_url FROM riders WHERE id = ? AND is_active = true",
      [req.user.id],
    );

    if (riders.length === 0) {
      return res.status(403).json({
        success: false,
        message: "Rider account is inactive or not found. Access denied.",
      });
    }

    res.json({
      success: true,
      rider: riders[0],
    });
  } catch (error) {
    console.error("Error fetching rider profile:", error);
    res.status(500).json({
      success: false,
      message: "Failed to fetch rider profile",
      error: error.message,
    });
  }
});

// Update rider location
router.put(
  "/rider/location",
  authenticateToken,
  [
    body("latitude").isFloat().withMessage("Invalid latitude"),
    body("longitude").isFloat().withMessage("Invalid longitude"),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: "Validation failed",
          errors: errors.array(),
        });
      }

      if (req.user.user_type !== "rider") {
        return res.status(403).json({
          success: false,
          message: "Access denied. Rider only.",
        });
      }

      const { latitude, longitude } = req.body;
      const riderId = req.user.id;

      await ensureRiderLocationColumns(req.db);

      // Update rider location in database
      await req.db.execute(
        `UPDATE orders SET rider_latitude = ?, rider_longitude = ?
             WHERE rider_id = ? AND status = 'out_for_delivery'`,
        [latitude, longitude, riderId],
      );

      // Also store in a rider location log table if available
      try {
        await req.db.execute(
          `INSERT INTO rider_location_logs (rider_id, latitude, longitude) VALUES (?, ?, ?)`,
          [riderId, latitude, longitude],
        );
      } catch (e) {
        // Table might not exist yet, that's okay
      }

      res.json({
        success: true,
        message: "Location updated successfully",
        location: { latitude, longitude },
      });
    } catch (error) {
      console.error("Error updating rider location:", error);
      res.status(500).json({
        success: false,
        message: "Failed to update location",
        error: error.message,
      });
    }
  },
);

// Get rider wallet stats (Daily, Weekly, Monthly)
router.get("/rider/wallet-stats", authenticateToken, async (req, res) => {
  try {
    if (req.user.user_type !== "rider") {
      return res.status(403).json({
        success: false,
        message: "Access denied. Rider only.",
      });
    }

    const riderId = req.user.id;
    const { period } = req.query; // daily, weekly, monthly

    // Check if rider exists and is active
    const [riders] = await req.db.execute(
      "SELECT id FROM riders WHERE id = ? AND is_active = true",
      [riderId],
    );

    if (riders.length === 0) {
      return res.status(403).json({
        success: false,
        message: "Rider account is inactive or not found. Access denied.",
      });
    }

    let dateCondition = "";
    if (period === "daily") {
      dateCondition = "DATE(o.created_at) = CURDATE()";
    } else if (period === "weekly") {
      dateCondition = "o.created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)";
    } else if (period === "monthly") {
      dateCondition = "o.created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)";
    } else {
      dateCondition = "DATE(o.created_at) = CURDATE()"; // Default to daily
    }

    // 1. Daily Cash Received (Items amount only for cash orders, excluding delivery fee)
    const [cashReceivedResult] = await req.db.execute(
      `
            SELECT COALESCE(SUM(total_amount - COALESCE(delivery_fee, 0)), 0) as total_cash
            FROM orders o
            WHERE o.rider_id = ? AND o.payment_method = 'cash' AND o.payment_status = 'paid' AND o.status = 'delivered' AND ${dateCondition}
        `,
      [riderId],
    );

    // 2. Delivery Fees (All delivered orders regardless of payment method)
    const [deliveryFeesResult] = await req.db.execute(
      `
            SELECT COALESCE(SUM(delivery_fee), 0) as total_delivery_fees
            FROM orders o
            WHERE o.rider_id = ? AND o.status = 'delivered' AND ${dateCondition}
        `,
      [riderId],
    );

    // 3. Payment Summary (Breakdown by payment method)
    const [summaryResult] = await req.db.execute(
      `
            SELECT 
                payment_method,
                COUNT(*) as order_count,
                SUM(total_amount) as total_amount,
                SUM(delivery_fee) as total_delivery_fees
            FROM orders o
            WHERE o.rider_id = ? AND o.status = 'delivered' AND ${dateCondition}
            GROUP BY payment_method
        `,
      [riderId],
    );

    res.json({
      success: true,
      stats: {
        period,
        cash_received: cashReceivedResult[0].total_cash,
        total_delivery_fees: deliveryFeesResult[0].total_delivery_fees,
        payment_summary: summaryResult,
      },
    });
  } catch (error) {
    console.error("Error fetching rider wallet stats:", error);
    res.status(500).json({
      success: false,
      message: "Failed to fetch wallet stats",
      error: error.message,
    });
  }
});

// Get store owner's dashboard orders
router.get(
  "/store-dashboard",
  authenticateToken,
  requireStoreOwner,
  async (req, res) => {
    try {
      await ensureOrderItemsSchema(req.db);
      const { status } = req.query;

      // Find stores owned by this user
      const [myStores] = await req.db.execute(
        "SELECT id, name FROM stores WHERE owner_id = ?",
        [req.user.id],
      );

      if (myStores.length === 0) {
        return res.json({ success: true, orders: [] });
      }

      const storeIds = myStores.map((s) => s.id);
      const placeholders = storeIds.map(() => "?").join(",");

      let query = `
            SELECT DISTINCT o.*, u.first_name, u.last_name, u.phone
            FROM orders o
            JOIN order_items oi ON o.id = oi.order_id
            JOIN users u ON o.user_id = u.id
            WHERE oi.store_id IN (${placeholders})
        `;
      const params = [...storeIds];

      if (status && status !== "all") {
        query += " AND o.status = ?";
        params.push(status);
      }

      query += " ORDER BY o.created_at DESC";

      const [orders] = await req.db.execute(query, params);

      // For each order, we only want to show items related to MY stores
      for (const order of orders) {
        const [items] = await req.db.execute(
          `
                SELECT oi.*, p.name as product_name, p.image_url
                FROM order_items oi
                JOIN products p ON oi.product_id = p.id
                WHERE oi.order_id = ? AND oi.store_id IN (${placeholders})
            `,
          [order.id, ...storeIds],
        );
        order.items = items;
      }

      // --- NEW: Calculate Dashboard Stats ---
      
      // 1. Order Counts (Distinct Orders)
      const [countRows] = await req.db.execute(`
          SELECT 
              COUNT(DISTINCT o.id) as total_orders,
              COUNT(DISTINCT CASE WHEN o.status = 'delivered' THEN o.id END) as delivered,
              COUNT(DISTINCT CASE WHEN o.status = 'preparing' THEN o.id END) as preparing,
              COUNT(DISTINCT CASE WHEN o.status = 'ready' THEN o.id END) as ready
          FROM orders o
          JOIN order_items oi ON o.id = oi.order_id
          WHERE oi.store_id IN (${placeholders})
      `, [...storeIds]);

      // 2. Total Revenue (Sum of items for this store in delivered orders)
      // Apply commission rate (default 10% if not set)
      // Formula: sum(price * quantity) * (1 - commission_rate/100)
      const [revenueRows] = await req.db.execute(`
          SELECT 
            COALESCE(
                SUM(
                    (oi.price * oi.quantity) * 
                    (1 - COALESCE(s.commission_rate, 10.00) / 100)
                ), 
            0) as revenue
          FROM order_items oi
          JOIN orders o ON oi.order_id = o.id
          JOIN stores s ON oi.store_id = s.id
          WHERE oi.store_id IN (${placeholders}) AND o.status = 'delivered'
      `, [...storeIds]);

      // 3. Wallet Balance (Received Balance)
      const [walletRows] = await req.db.execute(
          'SELECT balance FROM wallets WHERE user_id = ?', 
          [req.user.id]
      );
      const balance = walletRows.length > 0 ? walletRows[0].balance : 0;

      // 4. Get Store Name explicitly for dashboard display
      const [storeInfo] = await req.db.execute(
          'SELECT name FROM stores WHERE id = ?', 
          [myStores[0].id]
      );
      const storeName = storeInfo.length > 0 ? storeInfo[0].name : myStores[0].name;

      const stats = {
          store_id: myStores[0].id,
          store_name: storeName, // Ensure this is populated correctly
          total_orders: countRows[0].total_orders,
          delivered: countRows[0].delivered,
          preparing: countRows[0].preparing,
          ready: countRows[0].ready,
          total_amount: revenueRows[0].revenue,
          received_balance: balance
      };

      res.json({ success: true, orders, stats });
    } catch (error) {
      console.error("Error fetching store orders:", error);
      res.status(500).json({
        success: false,
        message: "Failed to fetch store orders",
        error: error.message,
      });
    }
  },
);

// Get single order details
router.get("/:id(\\d+)", authenticateToken, async (req, res) => {
  console.log(`[orders] Fetching order details for ID: ${req.params.id}`);
  try {
    const { id } = req.params;
    await ensureOrderItemsSchema(req.db);

    const [orders] = await req.db.execute(
      `
            SELECT o.*, u.first_name, u.last_name, u.email, u.phone, s.name as store_name,
                   r.first_name as rider_first_name, r.last_name as rider_last_name, r.phone as rider_phone
            FROM orders o
            JOIN users u ON o.user_id = u.id
            LEFT JOIN stores s ON o.store_id = s.id
            LEFT JOIN riders r ON o.rider_id = r.id
            WHERE o.id = ?
        `,
      [id],
    );

    console.log(`[orders] Found ${orders.length} orders for ID: ${id}`);

    if (orders.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Order not found",
      });
    }

    const order = orders[0];

    // Check permission: Admin, Standard User, Rider assigned, Customer who owns the order, or Store Owner linked to items
    let isStoreOwner = false;
    if (req.user.user_type === "store_owner") {
      // Check if this order contains items from any store owned by this user
      const [storeCheck] = await req.db.execute(
        `
            SELECT 1 
            FROM order_items oi
            JOIN stores s ON oi.store_id = s.id
            WHERE oi.order_id = ? AND s.owner_id = ?
            LIMIT 1
        `,
        [id, req.user.id],
      );
      if (storeCheck.length > 0) {
        isStoreOwner = true;
      }
    }

    if (
      req.user.user_type !== "admin" &&
      req.user.user_type !== "standard_user" &&
      req.user.id !== order.user_id &&
      req.user.user_type === "rider" &&
      req.user.id !== order.rider_id &&
      !isStoreOwner
    ) {
      return res.status(403).json({
        success: false,
        message: "Access denied",
      });
    }

    // Get order items with store info
    const [items] = await req.db.execute(
      `
            SELECT oi.*, p.name as product_name, p.image_url, s.name as store_name
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            LEFT JOIN stores s ON oi.store_id = s.id
            WHERE oi.order_id = ?
        `,
      [id],
    );

    order.items = items;

    // Group items by store for proper multi-store display
    const storeGroups = {};
    items.forEach((item) => {
      const sId = item.store_id || "unknown";
      if (!storeGroups[sId]) {
        storeGroups[sId] = {
          store_id: item.store_id,
          store_name: item.store_name || "Unknown Store",
          items: [],
        };
      }
      storeGroups[sId].items.push(item);
    });

    order.store_wise_items = Object.values(storeGroups);

    res.json({
      success: true,
      order,
    });
  } catch (error) {
    console.error("Error fetching order details:", error);
    res.status(500).json({
      success: false,
      message: "Failed to fetch order details",
      error: error.message,
    });
  }
});

// Helper to get store ID for owner
async function getStoreIdForOwner(db, userId) {
    const [rows] = await db.execute('SELECT id FROM stores WHERE owner_id = ? LIMIT 1', [userId]);
    return rows.length > 0 ? rows[0].id : null;
}

// Get all orders (Admin & Dispatch only)
router.get("/", authenticateToken, async (req, res) => {
  console.log(
    "[DEBUG] GET /api/orders hit. User:",
    req.user ? `${req.user.id} (${req.user.user_type})` : "No user",
  );
  try {
    // Permission check: Admin, Dispatch, or Dashboard Viewer
    if (req.user.user_type === "admin") {
      // Admin allowed
    } else if (req.user.user_type === "standard_user") {
      // Check for specific permissions
      try {
        // Debug permissions
        const [debugPerms] = await req.db.execute(
          "SELECT permission_key FROM user_permissions WHERE user_id = ?",
          [req.user.id],
        );
        console.log(
          `[DEBUG] Orders Route - User ${req.user.id} permissions:`,
          debugPerms.map((p) => p.permission_key),
        );

        const [perms] = await req.db.execute(
          "SELECT 1 FROM user_permissions WHERE user_id = ? AND permission_key IN (?, ?)",
          [req.user.id, "menu_dashboard", "menu_orders"],
        );
        if (perms.length === 0) {
          console.log(
            `[DEBUG] User ${req.user.id} denied access to orders. Missing menu_dashboard or menu_orders.`,
          );
          return res
            .status(403)
            .json({ success: false, message: "Access denied" });
        }
      } catch (e) {
        console.error("[DEBUG] Orders permission check error:", e);
        return res
          .status(500)
          .json({ success: false, message: "Permission check failed" });
      }
    } else {
      // Other roles (e.g. store owner) might need access logic here or be blocked
      return res.status(403).json({ success: false, message: "Access denied" });
    }

    const { status, assignment, startDate, endDate } = req.query;
    let conditions = [];
    let params = [];

    if (status && status !== "all") {
      conditions.push(`o.status = ?`);
      params.push(status);
    }

    if (assignment === "unassigned") {
      conditions.push(
        `o.rider_id IS NULL AND o.status NOT IN ('delivered', 'cancelled')`,
      );
    } else if (assignment === "assigned") {
      conditions.push(`o.rider_id IS NOT NULL`);
    }

    if (startDate) {
      conditions.push(`DATE(o.created_at) >= ?`);
      params.push(startDate);
    }

    if (endDate) {
      conditions.push(`DATE(o.created_at) <= ?`);
      params.push(endDate);
    }

    let whereClause = "";
    if (conditions.length > 0) {
      whereClause = "WHERE " + conditions.join(" AND ");
    }

    const [orders] = await req.db.execute(
      `
            SELECT o.*, u.first_name, u.last_name, u.email, s.name as store_name,
                   r.first_name as rider_first_name, r.last_name as rider_last_name,
                   CAST((SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS SIGNED) as items_count,
                   (
                       SELECT CONCAT('[', GROUP_CONCAT(JSON_OBJECT(
                           'store_id', s2.id, 
                           'store_name', s2.name, 
                           'status', COALESCE(oi2.item_status, 'pending')
                       )), ']')
                       FROM order_items oi2
                       JOIN stores s2 ON oi2.store_id = s2.id
                       WHERE oi2.order_id = o.id
                       GROUP BY oi2.order_id
                   ) as store_statuses
            FROM orders o
            JOIN users u ON o.user_id = u.id
            LEFT JOIN stores s ON o.store_id = s.id
            LEFT JOIN riders r ON o.rider_id = r.id
            ${whereClause}
            ORDER BY o.created_at DESC
        `,
      params,
    );

    res.json({
      success: true,
      orders,
    });
  } catch (error) {
    console.error("Error fetching orders:", error);
    res.status(500).json({
      success: false,
      message: "Failed to fetch orders",
      error: error.message,
    });
  }
});

// Update order status (Admin, Store Owner, or Standard User)
router.put(
  "/:id(\\d+)/status",
  authenticateToken,
  requireStaffAccess,
  [
    body("status")
      .isIn([
        "pending",
        "confirmed",
        "preparing",
        "ready",
        "ready_for_pickup", // New status
        "picked_up", // New status
        "delivered",
        "cancelled",
        "out_for_delivery",
      ])
      .withMessage("Invalid status"),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: "Validation failed",
          errors: errors.array(),
        });
      }

      const { id } = req.params;
      const { status } = req.body;
      const itemStatusForDB = status === 'picked_up' ? 'out_for_delivery' : (status === 'ready_for_pickup' ? 'ready' : status);

      // Check if order exists and user has permission
      // NOTE: For multi-store orders, o.store_id might be null or one of them. 
      // We need to check if the user owns ANY of the stores in this order.
      const [orders] = await req.db.execute(
        `
            SELECT o.*, s.owner_id as main_store_owner_id
            FROM orders o
            LEFT JOIN stores s ON o.store_id = s.id
            WHERE o.id = ?
        `,
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      // Check permission
      let hasPermission = false;
      if (req.user.user_type === "admin" || req.user.user_type === "standard_user") {
          hasPermission = true;
      } else if (req.user.user_type === "store_owner") {
          // Check if this user owns ANY store involved in this order
          const [myStores] = await req.db.execute(
              `SELECT 1 FROM order_items oi
               JOIN stores s ON oi.store_id = s.id
               WHERE oi.order_id = ? AND s.owner_id = ?
               LIMIT 1`,
              [id, req.user.id]
          );
          if (myStores.length > 0) {
              hasPermission = true;
          }
      }

      if (!hasPermission) {
        return res.status(403).json({
          success: false,
          message: "You do not have permission to update this order",
        });
      }

      // --- Multi-Store Status Logic ---

      // 1. Identify which items to update
      let targetItemIds = [];
      if (req.user.user_type === 'store_owner') {
          // Store Owner: Only update their own items
          const [myItems] = await req.db.execute(
              `SELECT oi.id FROM order_items oi 
               JOIN stores s ON oi.store_id = s.id 
               WHERE oi.order_id = ? AND s.owner_id = ?`,
              [id, req.user.id]
          );
          targetItemIds = myItems.map(i => i.id);
      } else {
          // Admin/Staff: Update ALL items (force sync)
          const [allItems] = await req.db.execute(
              'SELECT id FROM order_items WHERE order_id = ?', 
              [id]
          );
          targetItemIds = allItems.map(i => i.id);
      }

      // 2. Update Item Statuses
      if (targetItemIds.length > 0) {
          const placeholders = targetItemIds.map(() => '?').join(',');
          await req.db.execute(
              `UPDATE order_items SET item_status = ? WHERE id IN (${placeholders})`,
              [itemStatusForDB, ...targetItemIds]
          );
      }

      // 3. Recalculate Global Status
      // We need to know the status of ALL items to determine the global order status
      const [allOrderItems] = await req.db.execute(
          'SELECT item_status FROM order_items WHERE order_id = ?', 
          [id]
      );
      
      // Default nulls to 'pending'
      const statuses = allOrderItems.map(i => i.item_status || 'pending');
      
      let newGlobalStatus = 'pending';
      const uniqueStatuses = new Set(statuses);

      if (statuses.length === 0) {
          newGlobalStatus = status; // Fallback if no items
      } else if (uniqueStatuses.size === 1) {
          // All items have same status
          newGlobalStatus = statuses[0];
      } else {
          // Mixed statuses - Determine lowest common denominator
          const has = (s) => statuses.includes(s);
          
          // Custom logic: If status requested is 'ready_for_pickup', allow it to influence global state
          // The issue is if Store A is 'ready_for_pickup' and Store B is 'pending', global is 'preparing'.
          // But if Store A says 'ready_for_pickup', the customer should see 'ready' for Store A.
          
          if (statuses.every(s => s === 'cancelled')) {
              newGlobalStatus = 'cancelled';
          } else if (statuses.every(s => s === 'delivered' || s === 'cancelled')) {
              newGlobalStatus = 'delivered';
          } else if (has('out_for_delivery') || has('picked_up')) {
              // If any item is out/picked up, global status is out_for_delivery
              newGlobalStatus = 'out_for_delivery';
          } else if (has('ready_for_pickup')) {
              // If ANY item is ready for pickup, the order is effectively in a "ready" state for that store.
              // BUT for global status, if there are still items "preparing", global should stay "preparing".
              // If there are "ready" and "ready_for_pickup" and no "preparing", then global is "ready".
              
              const activeStatuses = statuses.filter(s => !['delivered', 'cancelled'].includes(s));
              // Check if anything is still preparing or pending
              if (activeStatuses.some(s => ['preparing', 'pending', 'confirmed'].includes(s))) {
                  // If specifically THIS request was setting it to ready_for_pickup, we want to ensure
                  // the frontend reflects this progress, but 'preparing' is technically correct for the whole order.
                  newGlobalStatus = 'preparing';
              } else {
                  // Everything is at least ready or ready_for_pickup
                  newGlobalStatus = 'ready';
              }
          } else if (has('preparing')) {
              // If any item is still preparing, the whole order is preparing
              newGlobalStatus = 'preparing';
          } else if (has('pending') || has('confirmed')) {
              // If things are ready but some are still pending/confirmed (not started), it's confirmed/pending
              // But effectively "Preparing" is a better summary if work has started elsewhere? 
              // No, if Store A is Ready and Store B is Pending, we are waiting.
              // Let's stick to: If ANY is preparing, it's preparing.
              // If ALL are Ready (ignoring done ones), it's Ready.
              const activeStatuses = statuses.filter(s => !['delivered', 'cancelled'].includes(s));
              if (activeStatuses.every(s => s === 'ready')) {
                  newGlobalStatus = 'ready';
              } else if (activeStatuses.some(s => s === 'preparing')) {
                  newGlobalStatus = 'preparing';
              } else {
                  // Mixed Ready + Pending? effectively "Confirmed" or "Preparing"?
                  // Let's say "Preparing" to indicate work is needed/ongoing.
                  newGlobalStatus = 'preparing';
              }
          } else {
              newGlobalStatus = 'preparing'; // Default fallthrough
          }
      }

      await req.db.execute("UPDATE orders SET status = ? WHERE id = ?", [
        newGlobalStatus,
        id,
      ]);

      // Emit order_status_update event - only to specific rooms to avoid duplicates
      try {
        if (req.io) {
          const statusUpdateData = {
            id: id,
            order_number: order.order_number,
            status: newGlobalStatus, // Emit the calculated global status
            user_id: order.user_id,
            updated_at: new Date(),
            // ADDED: Include which specific store updated which status
            store_update: req.user.user_type === 'store_owner' ? {
                store_id: req.user.store_id || (await getStoreIdForOwner(req.db, req.user.id)),
                status: status, // The specific status requested (e.g., 'preparing')
                item_ids: targetItemIds
            } : null
          };
          
          // Send to user room only (avoid duplicate by not sending to all)
          req.io
            .to(`user_${order.user_id}`)
            .emit("order_status_update", statusUpdateData);
          req.io.to("admins").emit("order_status_update", statusUpdateData);

          // Custom logic: Only emit 'notification' event for user-facing status changes
          // Avoid spamming generic notifications.
          
          if (status === 'picked_up') {
              // ... existing picked_up logic ...
              // Fetch Store Name and Rider Name for the message
              const [details] = await req.db.execute(
                  `SELECT s.name as store_name, r.first_name as rider_name 
                   FROM order_items oi
                   JOIN stores s ON oi.store_id = s.id
                   LEFT JOIN orders o ON oi.order_id = o.id
                   LEFT JOIN riders r ON o.rider_id = r.id
                   WHERE oi.id = ?`,
                  [targetItemIds[0]] // Use first item to get store/rider details
              );
              
              if (details.length > 0) {
                  const { store_name, rider_name } = details[0];
                  const message = `Your order #${order.order_number} containing ${store_name} products has been picked up by rider ${rider_name || 'Assigned Rider'}. Please act accordingly.`;
                  
                  // Emit specific notification event
                  req.io.to(`user_${order.user_id}`).emit('notification', {
                      type: 'order_update',
                      title: 'Order Picked Up',
                      message: message,
                      order_id: id
                  });
              }
          } else if (status === 'ready_for_pickup') {
              // ALSO notify when "Ready for Pickup"
              const [details] = await req.db.execute(
                  `SELECT s.name as store_name FROM stores s WHERE s.id = (SELECT store_id FROM order_items WHERE id = ? LIMIT 1)`,
                  [targetItemIds[0]]
              );
              
              if (details.length > 0) {
                  const { store_name } = details[0];
                  req.io.to(`user_${order.user_id}`).emit('notification', {
                      type: 'order_update',
                      title: 'Order Ready',
                      message: `Your items from ${store_name} are ready for pickup.`,
                      order_id: id
                  });
              }
          } else if (status === 'preparing' || status === 'ready') {
              // For preparing/ready, send a silent refresh only, OR a less intrusive notification if desired.
              // The user asked to STOP excessive notifications.
              // So for "Preparing", we just send the refresh signal, no visible toast needed unless customer is staring at screen.
              req.io.to(`user_${order.user_id}`).emit('user_notification', {
                  type: 'refresh_orders', // This triggers refresh but no toast in updated mobile code
                  message: '', 
                  order_id: id
              });
          }

          // Always ensure data is fresh on customer side (redundant but safe)
          if (status !== 'preparing' && status !== 'ready') {
             req.io.to(`user_${order.user_id}`).emit('user_notification', {
                type: 'refresh_orders',
                message: 'Order status updated',
                order_id: id
             });
          }
          
          // NEW: Notify Store Owners as well so their dashboard updates automatically
          // We need to notify ALL store owners involved in this order, not just the one who made the change
          // because if one store updates, the others might see a change in global status or just need a refresh.
          const [storeOwners] = await req.db.execute(
            `SELECT DISTINCT s.owner_id 
             FROM order_items oi
             JOIN stores s ON oi.store_id = s.id
             WHERE oi.order_id = ?`,
            [id]
          );
          
          for (const owner of storeOwners) {
              if (owner.owner_id) {
                  // Use 'silent_refresh' type to avoid visible notifications on other stores
                  req.io.to(`user_${owner.owner_id}`).emit('store_owner_notification', {
                      type: 'silent_refresh',
                      order_id: id,
                      message: '' 
                  });
              }
          }

          const fs = require("fs");
          const path = require("path");
          const logMsg = `[${new Date().toISOString()}] Status updated: ${order.order_number} -> ${newGlobalStatus} (Requested: ${status}). Store Owner Update: ${req.user.user_type === 'store_owner'}. Total clients: ${req.io.engine.clientsCount}\n`;
          fs.appendFile(
            path.join(__dirname, "../socket_debug.log"),
            logMsg,
            () => {},
          );
        }
      } catch (e) {
        console.error("Socket emit error:", e);
      }

      res.json({
        success: true,
        message: "Order status updated successfully",
        global_status: newGlobalStatus
      });
    } catch (error) {
      console.error("Error updating order:", error);
      res.status(500).json({
        success: false,
        message: "Failed to update order",
        error: error.message,
      });
    }
  },
);

// Assign rider to order (Admin only)
router.put(
  "/:id(\\d+)/assign-rider",
  authenticateToken,
  requireDispatchAccess,
  [
    body("rider_id").isInt().withMessage("Rider ID must be a valid integer"),
    body("delivery_fee")
      .optional()
      .isFloat({ min: 0 })
      .withMessage("Invalid delivery fee"),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: "Validation failed",
          errors: errors.array(),
        });
      }

      const { id } = req.params;
      const { rider_id, delivery_fee } = req.body;

      // Check if order exists
      const [orders] = await req.db.execute(
        "SELECT id, order_number, user_id, total_amount, delivery_fee, status FROM orders WHERE id = ?",
        [id],
      );
      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      // Do not allow assigning riders to already completed or cancelled orders
      if (order.status === "delivered" || order.status === "cancelled") {
        return res.status(400).json({
          success: false,
          message: `Cannot assign rider to an order that is already ${order.status}`,
        });
      }

      // Check if rider exists and is available
      const [riders] = await req.db.execute(
        "SELECT id, first_name, last_name FROM riders WHERE id = ? AND is_active = true",
        [rider_id],
      );
      if (riders.length === 0) {
        return res.status(400).json({
          success: false,
          message: "Rider not found or not active",
        });
      }

      const rider = riders[0];

      // Set estimated delivery time (current time + 30 minutes)
      const estimatedDelivery = new Date(Date.now() + 30 * 60 * 1000);

      // Recalculate total based on actual items
      const [items] = await req.db.execute(
        "SELECT price, quantity FROM order_items WHERE order_id = ?",
        [id],
      );

      let itemsSubtotal = 0;
      for (const item of items) {
        itemsSubtotal +=
          (parseFloat(item.price) || 0) * (parseInt(item.quantity) || 0);
      }

      let newTotal = order.total_amount;
      let finalDeliveryFee = parseFloat(order.delivery_fee) || 0;

      if (delivery_fee !== undefined) {
        finalDeliveryFee = parseFloat(delivery_fee);
        newTotal = Number(itemsSubtotal) + Number(finalDeliveryFee);
      } else if (itemsSubtotal > 0) {
        // Ensure total_amount is correct even if delivery_fee is not being updated
        newTotal = parseFloat(itemsSubtotal) + parseFloat(finalDeliveryFee);
      }

      // Assign rider and update status
      // NOTE: We only update global status to 'out_for_delivery' if it was 'ready' or 'pending'.
      // If it was already 'out_for_delivery' or 'delivered', we shouldn't revert it.
      // But actually, assigning a rider usually implies the process is moving forward.
      // However, if we blindly set 'out_for_delivery', it might override 'preparing' or 'ready' logic.
      // If items are still 'preparing', the global status should arguably stay 'preparing' until pickup?
      // BUT typically "Assigned" means the rider is on the way. 
      // The issue user reported: "it again gone preparing status in store dashboard"
      // This implies we MIGHT be setting it to something that triggers a revert, OR we are NOT updating item statuses?
      //
      // Wait, the user said: "it again gone preparing status in store dashboard and preparing too with store info"
      // If we set global status to 'out_for_delivery', the store dashboard (which filters Active = preparing/ready/out_for_delivery) shows it.
      // But why "preparing"?
      // Ah, maybe the frontend or backend logic reverts it?
      //
      // If we look at the store dashboard logic:
      // Active = preparing || ready || out_for_delivery
      //
      // If the admin assigns a rider, the status becomes 'out_for_delivery' here (line 1877).
      //
      // BUT, if the Store Owner had marked their items as "Ready", and now we assign a rider...
      // Does assigning a rider change ITEM statuses? No.
      //
      // If the global status is 'out_for_delivery', but item status is 'ready', what does the dashboard show?
      // The dashboard shows the item status if available, or global status if not.
      //
      // If the user sees "preparing", it means either:
      // 1. The global status became "preparing" (unlikely here, we set it to out_for_delivery).
      // 2. The item status is still "preparing".
      //
      // "when assign order to rider after making all stores ready in admin panel"
      // If admin makes stores ready, they likely used the "Update Status" feature.
      //
      // If we assign a rider, we explicitly set status = 'out_for_delivery'.
      //
      // Let's check if we are overwriting something we shouldn't.
      //
      // Use case: Admin sets status to "Ready" (Global). Items might be updated to "Ready".
      // Then Admin assigns Rider.
      // This route updates global status to 'out_for_delivery'.
      //
      // If item statuses are 'ready', and global is 'out_for_delivery', the store dashboard should show 'Ready' or 'Out for Delivery'?
      //
      // Let's look at store_owner_dashboard_screen.dart again (from memory/previous reads):
      // It displays `item['item_status']` if available.
      //
      // If the item status is "preparing", it shows preparing.
      //
      // The user says: "after making all stores ready in admin panel".
      // If the admin panel updates status, it calls `PUT /:id/status`.
      // That endpoint updates `order_items` AND recalculates global status.
      //
      // If the admin assigns a rider, it calls `POST /:id/assign-rider`.
      // This endpoint (here) updates `orders` table but NOT `order_items`.
      //
      // If `order_items` were 'ready', they remain 'ready'.
      //
      // However, if the user sees "preparing", it implies `order_items` are 'preparing'.
      //
      // HYPOTHESIS: The Admin Panel "Make Ready" button might NOT be updating `order_items` correctly for all stores?
      // OR, when assigning a rider, we trigger some side effect?
      //
      // Actually, if we set global status to 'out_for_delivery', we should probably NOT force it if items aren't ready?
      // OR, we should just let it be.
      //
      // Wait, if the global status is 'out_for_delivery', but items are 'ready', the store owner sees 'ready'.
      //
      // If the user says it "gone preparing", it means `item_status` reverted to `preparing` OR global status became `preparing`.
      //
      // Let's look at the `PUT /:id/status` logic again (it was in previous turns).
      // It updates `order_items`.
      //
      // Here in `assign-rider`, we set global status to `out_for_delivery`.
      //
      // Is there any hook that runs on `out_for_delivery`?
      //
      // Maybe the issue is simpler: When a rider is assigned, we should probably NOT change the status to `out_for_delivery` immediately?
      // Usually "Out for Delivery" means the rider picked it up.
      // "Assigned" just means "Rider Assigned" (status could be 'ready' or 'preparing').
      //
      // If we set it to 'out_for_delivery' immediately upon assignment, that might be premature.
      //
      // If we change this to keep the existing status (or only update if it's pending), that might fix the confusion.
      //
      // Let's check what the current status is.
      // If status is 'ready', and we assign rider, it should probably stay 'ready' (or 'ready_for_pickup').
      //
      // If I change line 1877 to use the existing status (unless it's pending), that might be safer.
      //
      // BUT, usually assigning a rider moves it to "Accepted" or something.
      //
      // User said: "it again gone preparing".
      // This strongly suggests something is resetting the status.
      //
      // Let's look at line 1874: `UPDATE orders SET ... status = 'out_for_delivery' ...`
      // This forces global status to `out_for_delivery`.
      //
      // If the Store Owner dashboard sees `out_for_delivery`, it should show that?
      //
      // Unless... `_getStatusColor` or logic in dashboard defaults to something else?
      //
      // Wait! I recall the store dashboard logic:
      // `_activeOrders` includes `preparing`, `ready`, `out_for_delivery`.
      //
      // If the user says it "gone preparing", it implies the TEXT says "Preparing".
      //
      // Let's try to preserve the current status if it is 'ready' or 'preparing'.
      // Only change to 'confirmed' or 'preparing' if it was 'pending'?
      //
      // Actually, if a rider is assigned, the status shouldn't necessarily jump to `out_for_delivery`.
      // `out_for_delivery` usually happens when Rider clicks "Pick Up".
      //
      // So, I should change this to NOT force `out_for_delivery`.
      // I should leave the status as is, OR set it to 'confirmed'/ 'preparing' if it was pending.
      //
      // If the order was 'ready', it should stay 'ready'.
      // If the order was 'preparing', it should stay 'preparing'.
      //
      // So, I will remove `status = 'out_for_delivery'` from the update query,
      // OR only update it if it's currently 'pending'.
      
      let newStatus = order.status;
      if (order.status === 'pending') {
          newStatus = 'confirmed'; // or 'preparing'
      }
      // If it's already 'ready' or 'preparing', keep it.
      
      await req.db.execute(
        "UPDATE orders SET rider_id = ?, status = ?, estimated_delivery_time = ?, delivery_fee = ?, total_amount = ? WHERE id = ?",
        [
          rider_id,
          newStatus,
          estimatedDelivery,
          finalDeliveryFee,
          newTotal,
          id,
        ],
      );

      // Emit order_assigned event
      try {
        if (req.io) {
          const orderData = {
            id: id,
            order_number: order.order_number,
            rider_id: rider_id,
            rider_name: `${rider.first_name} ${rider.last_name}`,
            status: newStatus, // Send the ACTUAL new status, not hardcoded 'out_for_delivery'
            estimated_delivery_time: estimatedDelivery,
            delivery_fee: finalDeliveryFee,
            total_amount: newTotal,
          };

          console.log(
            `[Orders] Broadcasting order_assigned to admins`,
            orderData,
          );
          req.io.to("admins").emit("order_assigned", orderData);

          // NEW: Send "Store Owner Notification" to all store owners involved in this order
          // Identify unique stores in this order
          const [storeOwners] = await req.db.execute(
            `SELECT DISTINCT s.owner_id, s.name as store_name
             FROM order_items oi
             JOIN stores s ON oi.store_id = s.id
             WHERE oi.order_id = ?`,
            [id]
          );

          for (const owner of storeOwners) {
              const message = `Order #${order.order_number} containing ${owner.store_name} products has been assigned to rider ${rider.first_name} ${rider.last_name}.`;
              
              // Emit specific notification event to store owner
              // Assuming store owners join room 'user_{id}' just like customers
              req.io.to(`user_${owner.owner_id}`).emit('store_owner_notification', {
                  type: 'rider_assigned',
                  title: 'Rider Assigned',
                  message: message,
                  order_id: id,
                  rider_name: `${rider.first_name} ${rider.last_name}`
              });

              // Log notification
              const logMsg = `[${new Date().toISOString()}] Store notification sent to owner ${owner.owner_id} for store ${owner.store_name}\n`;
              const fs = require("fs");
              const path = require("path");
              fs.appendFile(path.join(__dirname, "../socket_debug.log"), logMsg, () => {});
          }

          const riderRoomName = `rider_${rider_id}`;
          const userRoomName = `user_${order.user_id}`;

          console.log(
            `[Orders] Emitting rider_notification to room: ${riderRoomName}`,
            { rider_id, order_number: order.order_number },
          );
          req.io.to(riderRoomName).emit("rider_notification", {
            type: "assigned",
            rider_id: rider_id,
            order_id: id,
            order_number: order.order_number,
            message: `New order assigned: ${order.order_number}`,
            timestamp: new Date(),
          });

          console.log(
            `[Orders] Emitting user_notification to room: ${userRoomName}`,
            { user_id: order.user_id, order_number: order.order_number },
          );
          req.io.to(userRoomName).emit("user_notification", {
            type: "order_update",
            user_id: order.user_id,
            order_id: id,
            order_number: order.order_number,
            status: "out_for_delivery",
            message: `Your order ${order.order_number} has been assigned to rider ${rider.first_name}.`,
            timestamp: new Date(),
          });
          
          const fs = require("fs");
          const path = require("path");
          const logMsg = `[${new Date().toISOString()}] Order assigned: ${order.order_number} to ${rider.first_name}. Sent to rooms: ${riderRoomName}, ${userRoomName}\n`;
          fs.appendFile(
            path.join(__dirname, "../socket_debug.log"),
            logMsg,
            () => {},
          );
        }
      } catch (e) {
        console.error("Socket emit error:", e);
      }

      res.json({
        success: true,
        message: "Rider assigned successfully",
        delivery_fee: finalDeliveryFee,
        total_amount: newTotal,
      });
    } catch (error) {
      console.error("Error assigning rider:", error);
      res.status(500).json({
        success: false,
        message: "Failed to assign rider",
        error: error.message,
      });
    }
  },
);

// Update delivery fee (Admin only) - Auto-calculates based on unique stores in order
// Update delivery fee (Admin or Standard User)
router.put(
  "/:id(\\d+)/delivery-fee",
  authenticateToken,
  requireStaffAccess,
  async (req, res) => {
    try {
      const { id } = req.params;
      const { delivery_fee: manual_delivery_fee } = req.body;

      // Check if order exists
      const [orders] = await req.db.execute(
        "SELECT id, total_amount, delivery_fee as old_delivery_fee FROM orders WHERE id = ?",
        [id],
      );
      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      // Get order items to calculate items subtotal
      const [items] = await req.db.execute(
        `
            SELECT DISTINCT store_id, price, quantity FROM order_items WHERE order_id = ?
        `,
        [id],
      );

      // Calculate items subtotal from actual items
      let itemsSubtotal = 0;
      for (const item of items) {
        itemsSubtotal +=
          (parseFloat(item.price) || 0) * (parseInt(item.quantity) || 0);
      }

      let delivery_fee;
      let is_manual = false;

      if (manual_delivery_fee !== undefined && manual_delivery_fee !== null) {
        delivery_fee = parseFloat(manual_delivery_fee);
        if (isNaN(delivery_fee)) {
          return res
            .status(400)
            .json({ success: false, message: "Invalid delivery fee provided" });
        }
        is_manual = true;
      } else {
        // Count unique stores for auto-calculation
        const storeIds = new Set(
          items.map((item) => item.store_id).filter(Boolean),
        );
        const storeCount = storeIds.size;

        // Calculate delivery fee based on number of unique stores
        if (storeCount === 1) {
          delivery_fee = 70;
        } else if (storeCount === 2) {
          delivery_fee = 100;
        } else if (storeCount >= 3) {
          delivery_fee = 130 + (storeCount - 3) * 30;
        } else {
          delivery_fee = 70;
        }
      }

      // Recalculate total from items subtotal
      const newTotal = itemsSubtotal + delivery_fee;

      // Update delivery fee and total
      await req.db.execute(
        "UPDATE orders SET delivery_fee = ?, total_amount = ? WHERE id = ?",
        [Number(delivery_fee), newTotal, id],
      );

      res.json({
        success: true,
        message: is_manual
          ? "Delivery fee updated manually"
          : "Delivery fee auto-calculated and updated successfully",
        delivery_fee: parseFloat(delivery_fee),
        total_amount: newTotal,
      });
    } catch (error) {
      console.error("Error updating delivery fee:", error);
      res.status(500).json({
        success: false,
        message: "Failed to update delivery fee",
        error: error.message,
      });
    }
  },
);

// Update rider location (Rider or Admin)
router.put(
  "/:id(\\d+)/rider-location",
  authenticateToken,
  [
    body("latitude").optional().isFloat().withMessage("Invalid latitude"),
    body("longitude").optional().isFloat().withMessage("Invalid longitude"),
    body("location").optional().notEmpty().withMessage("Location is required"),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: "Validation failed",
          errors: errors.array(),
        });
      }

      const { id } = req.params;
      const { location, latitude, longitude } = req.body;

      // Check if order exists and user has permission (rider or admin)
      const [orders] = await req.db.execute(
        "SELECT id, rider_id, user_id, order_number, total_amount, payment_status, status FROM orders WHERE id = ?",
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      // Check ownership permission
      if (
        req.user.user_type !== "admin" &&
        req.user.user_type !== "standard_user" &&
        order.rider_id !== req.user.id
      ) {
        return res.status(403).json({
          success: false,
          message: "You do not have permission to update this order",
        });
      }

      await ensureRiderLocationColumns(req.db);

      if (latitude !== undefined && longitude !== undefined) {
        await req.db.execute(
          "UPDATE orders SET rider_latitude = ?, rider_longitude = ? WHERE id = ?",
          [latitude, longitude, id],
        );
      }

      res.json({
        success: true,
        message: "Rider location updated successfully",
      });
    } catch (error) {
      console.error("Error updating rider location:", error);
      res.status(500).json({
        success: false,
        message: "Failed to update rider location",
        error: error.message,
      });
    }
  },
);

// Mark order as delivered (Rider or Admin)
router.put("/:id(\\d+)/deliver", authenticateToken, async (req, res) => {
  try {
    const { id } = req.params;

    // Check if order exists and user has permission (rider, admin, or standard user)
    const [orders] = await req.db.execute(
      `SELECT o.id, o.rider_id, o.user_id, o.order_number, o.total_amount, o.delivery_fee, o.payment_method, o.payment_status, o.status,
                    u.email as user_email, u.first_name as user_first_name
             FROM orders o
             JOIN users u ON o.user_id = u.id
             WHERE o.id = ?`,
      [id],
    );

    if (orders.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Order not found",
      });
    }

    const order = orders[0];

    // Check ownership permission
    if (
      req.user.user_type !== "admin" &&
      req.user.user_type !== "standard_user" &&
      order.rider_id !== req.user.id
    ) {
      return res.status(403).json({
        success: false,
        message: "You do not have permission to update this order",
      });
    }

    await req.db.execute("UPDATE orders SET status = ? WHERE id = ?", [
      "delivered",
      id,
    ]);

    // Force update all order items to 'delivered' so they move to history in store dashboard
    await req.db.execute(
      "UPDATE order_items SET item_status = 'delivered' WHERE order_id = ?",
      [id]
    );

    // Notifications - only to specific rooms to avoid duplicates
    try {
      if (req.io) {
        // Status update to user room only (not to all)
        const statusUpdateData = {
          id: id,
          order_number: order.order_number,
          status: "delivered",
          user_id: order.user_id,
          updated_at: new Date(),
        };
        req.io
          .to(`user_${order.user_id}`)
          .emit("order_status_update", statusUpdateData);
        req.io.to("admins").emit("order_status_update", statusUpdateData);
        if (order.rider_id) {
          req.io.to(`rider_${order.rider_id}`).emit("order_status_update", {
            ...statusUpdateData,
            rider_id: order.rider_id,
          });
          req.io.to(`rider_${order.rider_id}`).emit("rider_notification", {
            type: "order_status_update",
            rider_id: order.rider_id,
            order_id: id,
            order_number: order.order_number,
            status: "delivered",
            message: `Order ${order.order_number} marked as delivered.`,
            timestamp: new Date(),
          });
        }

        const [storeOwners] = await req.db.execute(
          `SELECT DISTINCT s.owner_id
           FROM order_items oi
           JOIN stores s ON oi.store_id = s.id
           WHERE oi.order_id = ?`,
          [id],
        );
        for (const owner of storeOwners) {
          if (!owner.owner_id) continue;
          req.io.to(`user_${owner.owner_id}`).emit("store_owner_notification", {
            type: "order_status_update",
            order_id: id,
            order_number: order.order_number,
            status: "delivered",
            message: `Order ${order.order_number} delivered.`,
            timestamp: new Date(),
          });
        }

        // User notification
        const userNotifData = {
          type: "order_update",
          user_id: order.user_id,
          order_id: id,
          order_number: order.order_number,
          status: "delivered",
          message: `Your order ${order.order_number} has been delivered.`,
          timestamp: new Date(),
        };
        req.io
          .to(`user_${order.user_id}`)
          .emit("user_notification", userNotifData);

        // Admin notification
        const adminNotifData = {
          type: "order_update",
          order_id: id,
          order_number: order.order_number,
          status: "delivered",
          message: `Order ${order.order_number} has been delivered by rider.`,
          timestamp: new Date(),
        };
        req.io.to("admins").emit("user_notification", adminNotifData);

        // Check if completed (paid + delivered)
        if (order.payment_status === "paid") {
          const completedData = {
            id: id,
            order_number: order.order_number,
            user_id: order.user_id,
            total_amount: order.total_amount,
            message: `Thank you for choosing ServeNow! Your order ${order.order_number} has been completed and delivered.`,
            timestamp: new Date(),
          };
          // Send to user room only (not to all)
          req.io
            .to(`user_${order.user_id}`)
            .emit("order_completed", completedData);
          req.io.to("admins").emit("order_completed", completedData);

          // Send Thanks Email
          if (order.user_email) {
            sendOrderThanksEmail(
              order.user_email,
              order.user_first_name || "Customer",
              order.order_number,
            );
          }
        }
      }
    } catch (e) {
      console.error("Socket emit error in deliver:", e);
    }

    res.json({
      success: true,
      message: "Order marked as delivered successfully",
    });
  } catch (error) {
    console.error("Error marking order as delivered:", error);
    res.status(500).json({
      success: false,
      message: "Failed to mark order as delivered",
      error: error.message,
    });
  }
});

// Update payment status (Admin or Rider)
router.put(
  "/:id(\\d+)/payment-status",
  authenticateToken,
  [
    body("payment_status")
      .isIn(["pending", "paid", "failed"])
      .withMessage("Invalid payment status"),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: "Validation failed",
          errors: errors.array(),
        });
      }

      const { id } = req.params;
      const { payment_status } = req.body;

      if (!payment_status) {
        return res.status(400).json({
          success: false,
          message: "Payment status is required",
        });
      }

      // Check if order exists and user has permission (rider or admin)
      const [orders] = await req.db.execute(
        `SELECT o.id, o.rider_id, o.user_id, o.order_number, o.total_amount, o.delivery_fee, o.payment_method, o.payment_status, o.status,
                    u.email as user_email, u.first_name as user_first_name
             FROM orders o
             JOIN users u ON o.user_id = u.id
             WHERE o.id = ?`,
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      // Check ownership permission
      if (
        req.user.user_type !== "admin" &&
        req.user.user_type !== "standard_user" &&
        order.rider_id !== req.user.id
      ) {
        return res.status(403).json({
          success: false,
          message: "You do not have permission to update this order",
        });
      }

      await req.db.execute(
        "UPDATE orders SET payment_status = ? WHERE id = ?",
        [payment_status, id],
      );

      if (
        payment_status === "paid" &&
        order.rider_id &&
        order.payment_status !== "paid"
      ) {
        // New Financial Management Logic for Basic Delivery of Goods
        // Store: 100 (Cr.), Delivery Charges: 70 (Cr.), Rider: 170 (Dr.)
        const orderTotal = parseFloat(order.total_amount || 0);
        const deliveryFee = parseFloat(order.delivery_fee || 0);
        const storeAmount = orderTotal - deliveryFee;

        // 1. Credit the Store (Payable to store)
        await recordFinancialTransaction(req.db, {
          transaction_type: "adjustment", // Using adjustment for payable, settlement is for actual payout
          category: "store_payable",
          description: `Store Credit for Order #${order.order_number}`,
          amount: storeAmount,
          payment_method: order.payment_method,
          related_entity_type: "store",
          related_entity_id: order.store_id,
          reference_type: "order",
          reference_id: id,
          created_by: req.user.id,
          notes: "Store: 100 (Cr.)",
        });

        // 2. Credit Total Order Amount (Income)
        // We record the full amount as income, and payouts to stores/riders as settlements/expenses
        await recordFinancialTransaction(req.db, {
          transaction_type: "income",
          category: "order_revenue",
          description: `Total Revenue for Order #${order.order_number}`,
          amount: orderTotal,
          payment_method: order.payment_method,
          related_entity_type: "rider",
          related_entity_id: order.rider_id,
          reference_type: "order",
          reference_id: id,
          created_by: req.user.id,
          notes: `Gross Income: ${orderTotal} (Cr.)`,
        });

        // 3. Update Rider Wallet
        // Wallet balance in mobile app is treated as rider's available amount.
        // For cash orders, credit full collected amount.
        // For non-cash orders, credit only delivery fee earnings.
        const isCash = order.payment_method === "cash";
        const cashCollected = isCash ? parseFloat(order.total_amount || 0) : 0;
        const riderDrAmount = cashCollected;

        // Get or Create Wallet
        const [wallets] = await req.db.execute(
          "SELECT id, balance FROM wallets WHERE rider_id = ?",
          [order.rider_id],
        );

        let walletId;
        let currentBalance = 0;

        if (wallets.length > 0) {
          walletId = wallets[0].id;
          currentBalance = parseFloat(wallets[0].balance || 0);
        } else {
          await req.db.execute(
            "INSERT INTO wallets (rider_id, user_type, balance) VALUES (?, ?, ?)",
            [order.rider_id, "rider", 0],
          );
          const [newWallets] = await req.db.execute(
            "SELECT id FROM wallets WHERE rider_id = ?",
            [order.rider_id],
          );
          walletId = newWallets[0].id;
        }

        // 3a. Credit rider wallet
        const walletCreditAmount = isCash ? cashCollected : deliveryFee;
        if (walletCreditAmount > 0) {
          currentBalance += walletCreditAmount;
          await req.db.execute(
            "UPDATE wallets SET balance = ?, total_credited = total_credited + ? WHERE id = ?",
            [currentBalance, walletCreditAmount, walletId],
          );
          await req.db.execute(
            `INSERT INTO wallet_transactions (wallet_id, type, amount, description, reference_type, reference_id, balance_after) 
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [
              walletId,
              "credit",
              walletCreditAmount,
              isCash
                ? `Cash collection for order #${order.order_number}`
                : `Delivery fee for order #${order.order_number}`,
              "order",
              id,
              currentBalance,
            ],
          );
        }

        // Record Rider Dr in financial_transactions
        await recordFinancialTransaction(req.db, {
          transaction_type: "adjustment",
          category: "rider_receivable",
          description: `Rider Debit for Order #${order.order_number}`,
          amount: riderDrAmount,
          payment_method: order.payment_method,
          related_entity_type: "rider",
          related_entity_id: order.rider_id,
          reference_type: "order",
          reference_id: id,
          created_by: req.user.id,
          notes: `Rider's Balance: ${riderDrAmount} (Dr.)`,
        });

        // Create rider cash movement for cash payments
        if (order.payment_method === "cash") {
          try {
            const movementDate = new Date().toISOString().split("T")[0];
            const dateStr = movementDate.replace(/-/g, "");
            const randomStr = Math.random()
              .toString(36)
              .substring(2, 8)
              .toUpperCase();
            const movementNumber = `RCM-${dateStr}-${randomStr}`;

            await req.db.execute(
              `INSERT INTO rider_cash_movements 
                         (movement_number, rider_id, movement_date, movement_type, amount, description, reference_type, reference_id, status, recorded_by)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
              [
                movementNumber,
                order.rider_id,
                movementDate,
                "cash_collection",
                order.total_amount,
                `Cash collection for Order #${order.order_number}`,
                "order",
                id,
                "completed",
                req.user.user_type === "admin" ? req.user.id : null,
              ],
            );
          } catch (err) {
            console.error("Error creating rider cash movement:", err);
            // Don't fail the whole request if financial recording fails, but log it
          }
        }
      }

      // Notifications - only to specific rooms to avoid duplicates
      try {
        if (req.io) {
          const paymentUpdateData = {
            id: id,
            order_number: order.order_number,
            payment_status: payment_status,
            user_id: order.user_id,
            timestamp: new Date(),
          };
          // Send to user room only (not to all)
          req.io
            .to(`user_${order.user_id}`)
            .emit("payment_status_update", paymentUpdateData);
          req.io.to("admins").emit("payment_status_update", paymentUpdateData);

          // User notification
          const userPaymentNotif = {
            type: "payment_status_update",
            order_id: id,
            order_number: order.order_number,
            payment_status: payment_status,
            message: `Payment received for order ${order.order_number}.`,
            timestamp: new Date(),
          };
          req.io
            .to(`user_${order.user_id}`)
            .emit("user_notification", userPaymentNotif);

          // Admin notification
          const adminPaymentNotif = {
            type: "payment_status_update",
            order_id: id,
            order_number: order.order_number,
            payment_status: payment_status,
            message: `Payment ${payment_status} for order ${order.order_number}.`,
            timestamp: new Date(),
          };
          req.io.to("admins").emit("user_notification", adminPaymentNotif);

          // Check if completed (paid + delivered)
          if (payment_status === "paid" && order.status === "delivered") {
            const completedData = {
              id: id,
              order_number: order.order_number,
              user_id: order.user_id,
              total_amount: order.total_amount,
              message: `Thank you for choosing ServeNow! Your order ${order.order_number} has been completed and delivered.`,
              timestamp: new Date(),
            };
            // Send to user room only (not to all)
            req.io
              .to(`user_${order.user_id}`)
              .emit("order_completed", completedData);
            req.io.to("admins").emit("order_completed", completedData);

            // Send Thanks Email
            if (order.user_email) {
              sendOrderThanksEmail(
                order.user_email,
                order.user_first_name || "Customer",
                order.order_number,
              );
            }
          }
        }
      } catch (e) {
        console.error("Socket emit error in payment-status:", e);
      }

      res.json({
        success: true,
        message: "Payment status updated successfully",
      });
    } catch (error) {
      console.error("Error updating payment status:", error);
      res.status(500).json({
        success: false,
        message: "Failed to update payment status",
        error: error.message,
      });
    }
  },
);

router.put(
  "/:id(\\d+)/items",
  authenticateToken,
  requireStaffAccess,
  async (req, res) => {
    try {
      const { id } = req.params;
      const { items, store_id } = req.body;

      if (!Array.isArray(items) || items.length === 0) {
        return res.status(400).json({
          success: false,
          message: "Items array is required and cannot be empty",
        });
      }

      const [orders] = await req.db.execute(
        "SELECT * FROM orders WHERE id = ?",
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      if (order.status === "delivered" || order.status === "cancelled") {
        return res.status(400).json({
          success: false,
          message: `Cannot update items for ${order.status} orders`,
        });
      }

      let itemsSubtotal = 0;

      for (const item of items) {
        const { id: itemId, quantity } = item;

        if (!quantity || quantity < 1) {
          return res.status(400).json({
            success: false,
            message: "All items must have a quantity of at least 1",
          });
        }

        if (itemId) {
          const [existingItems] = await req.db.execute(
            "SELECT price FROM order_items WHERE id = ? AND order_id = ?",
            [itemId, id],
          );

          if (existingItems.length === 0) {
            return res.status(400).json({
              success: false,
              message: "Invalid item ID",
            });
          }

          const price = existingItems[0].price;
          const updateFields = ["quantity = ?"];
          const updateValues = [quantity];

          if (store_id && store_id !== null) {
            updateFields.push("store_id = ?");
            updateValues.push(store_id);
          }

          updateValues.push(itemId);
          updateValues.push(id);

          await req.db.execute(
            `UPDATE order_items SET ${updateFields.join(", ")} WHERE id = ? AND order_id = ?`,
            updateValues,
          );

          itemsSubtotal += price * quantity;
        }
      }

      // Recalculate totals and store_id from DB to ensure consistency across all items
      const [currentItems] = await req.db.execute(
        "SELECT SUM(quantity * price) as total, COUNT(DISTINCT store_id) as store_count, MAX(store_id) as single_store_id FROM order_items WHERE order_id = ?",
        [id],
      );

      const dbSubtotal = Number(currentItems[0]?.total || 0);
      const storeCount = currentItems[0]?.store_count || 0;
      let newOrderStoreId = null;

      // If all items belong to exactly one store, assign that store to the order
      if (storeCount === 1) {
        newOrderStoreId = currentItems[0]?.single_store_id;
      }
      // If storeCount > 1, newOrderStoreId remains null (Multiple Stores)

      const totalAmount = dbSubtotal + Number(order.delivery_fee || 0);

      await req.db.execute(
        "UPDATE orders SET total_amount = ?, store_id = ? WHERE id = ?",
        [totalAmount, newOrderStoreId, id],
      );

      res.json({
        success: true,
        message: "Order items updated successfully",
      });
    } catch (error) {
      console.error("Error updating order items:", error);
      res.status(500).json({
        success: false,
        message: "Failed to update order items",
        error: error.message,
      });
    }
  },
);

router.get(
  "/:id(\\d+)/items",
  authenticateToken,
  requireStaffAccess,
  async (req, res) => {
    try {
      const { id } = req.params;

      const [orders] = await req.db.execute(
        "SELECT id, status, store_id, total_amount, delivery_fee, rider_id, rider_location, rider_latitude, rider_longitude FROM orders WHERE id = ?",
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const [items] = await req.db.execute(
        `
            SELECT oi.id, oi.product_id, oi.quantity, oi.price, oi.store_id,
                   p.name as product_name, p.image_url,
                   s.name as store_name
            FROM order_items oi
            JOIN products p ON oi.product_id = p.id
            LEFT JOIN stores s ON oi.store_id = s.id
            WHERE oi.order_id = ?
            ORDER BY oi.id ASC
        `,
        [id],
      );

      const [stores] = await req.db.execute(`
            SELECT DISTINCT s.id, s.name
            FROM stores s
            INNER JOIN products p ON s.id = p.store_id
            WHERE s.is_active = true AND p.is_available = true
            ORDER BY s.name ASC
        `);

      res.json({
        success: true,
        order: orders[0],
        items: items || [],
        availableStores: stores || [],
      });
    } catch (error) {
      console.error("Error fetching order items:", error);
      res.status(500).json({
        success: false,
        message: "Failed to fetch order items",
        error: error.message,
      });
    }
  },
);

router.post(
  "/:id(\\d+)/items/add",
  authenticateToken,
  requireStaffAccess,
  async (req, res) => {
    try {
      const { id } = req.params;
      const { product_id, quantity, store_id } = req.body;

      if (!product_id || !quantity || quantity < 1) {
        return res.status(400).json({
          success: false,
          message: "Product ID and quantity (minimum 1) are required",
        });
      }

      const [orders] = await req.db.execute(
        "SELECT * FROM orders WHERE id = ?",
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      if (order.status === "delivered" || order.status === "cancelled") {
        return res.status(400).json({
          success: false,
          message: `Cannot add items to ${order.status} orders`,
        });
      }

      const [products] = await req.db.execute(
        "SELECT id, price, cost_price, store_id, discount_type, discount_value FROM products WHERE id = ? AND is_available = true",
        [product_id],
      );

      if (products.length === 0) {
        return res.status(400).json({
          success: false,
          message: "Product not found or unavailable",
        });
      }

      const product = products[0];
      const price = product.price;

      const itemStoreId =
        store_id || order.store_id || product.store_id || null;

      const [result] = await req.db.execute(
        `
            INSERT INTO order_items (order_id, product_id, quantity, price, store_id, discount_type, discount_value)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        `,
        [
          id,
          product_id,
          quantity,
          price,
          itemStoreId,
          product.discount_type,
          product.discount_value,
        ],
      );

      const [currentItems] = await req.db.execute(
        "SELECT SUM(quantity * price) as total, COUNT(DISTINCT store_id) as store_count, MAX(store_id) as single_store_id FROM order_items WHERE order_id = ?",
        [id],
      );

      const itemsSubtotal = Number(currentItems[0]?.total || 0);
      const storeCount = currentItems[0]?.store_count || 0;
      let newOrderStoreId = null;

      if (storeCount === 1) {
        newOrderStoreId = currentItems[0]?.single_store_id;
      }

      const newTotal = itemsSubtotal + Number(order.delivery_fee || 0);
      await req.db.execute(
        "UPDATE orders SET total_amount = ?, store_id = ? WHERE id = ?",
        [newTotal, newOrderStoreId, id],
      );

      res.json({
        success: true,
        message: "Item added successfully",
        item_id: result.insertId,
      });
    } catch (error) {
      console.error("Error adding item to order:", error);
      res.status(500).json({
        success: false,
        message: "Failed to add item to order",
        error: error.message,
      });
    }
  },
);

router.delete(
  "/:id(\\d+)/items/:itemId(\\d+)",
  authenticateToken,
  requireStaffAccess,
  async (req, res) => {
    try {
      const { id, itemId } = req.params;

      const [orders] = await req.db.execute(
        "SELECT * FROM orders WHERE id = ?",
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const order = orders[0];

      if (order.status === "delivered" || order.status === "cancelled") {
        return res.status(400).json({
          success: false,
          message: `Cannot remove items from ${order.status} orders`,
        });
      }

      const [items] = await req.db.execute(
        "SELECT id FROM order_items WHERE id = ? AND order_id = ?",
        [itemId, id],
      );

      if (items.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Item not found in this order",
        });
      }

      await req.db.execute(
        "DELETE FROM order_items WHERE id = ? AND order_id = ?",
        [itemId, id],
      );

      const [currentItems] = await req.db.execute(
        "SELECT SUM(quantity * price) as total, COUNT(DISTINCT store_id) as store_count, MAX(store_id) as single_store_id FROM order_items WHERE order_id = ?",
        [id],
      );

      const itemsSubtotal = Number(currentItems[0]?.total || 0);
      const storeCount = currentItems[0]?.store_count || 0;
      let newOrderStoreId = null;

      if (storeCount === 1) {
        newOrderStoreId = currentItems[0]?.single_store_id;
      }

      const newTotal = itemsSubtotal + Number(order.delivery_fee || 0);
      await req.db.execute(
        "UPDATE orders SET total_amount = ?, store_id = ? WHERE id = ?",
        [newTotal, newOrderStoreId, id],
      );

      const [remainingItems] = await req.db.execute(
        "SELECT COUNT(*) as count FROM order_items WHERE order_id = ?",
        [id],
      );

      if (remainingItems[0].count === 0) {
        return res.json({
          success: true,
          message: "Item removed. Order has no items left.",
          empty: true,
        });
      }

      res.json({
        success: true,
        message: "Item removed successfully",
      });
    } catch (error) {
      console.error("Error removing item from order:", error);
      res.status(500).json({
        success: false,
        message: "Failed to remove item from order",
        error: error.message,
      });
    }
  },
);

router.get(
  "/:id(\\d+)/available-products",
  authenticateToken,
  requireAdmin,
  async (req, res) => {
    try {
      const { id } = req.params;
      const { store_id } = req.query;

      const [orders] = await req.db.execute(
        "SELECT store_id FROM orders WHERE id = ?",
        [id],
      );

      if (orders.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Order not found",
        });
      }

      const orderStoreId = orders[0].store_id;
      const filterStoreId = store_id || orderStoreId;

      let query = `
            SELECT p.id, p.name, p.price
            FROM products p
            INNER JOIN stores s ON p.store_id = s.id
            WHERE p.is_available = true AND s.is_active = true
        `;

      const params = [];

      if (filterStoreId) {
        query += " AND p.store_id = ?";
        params.push(filterStoreId);
      }

      query += " ORDER BY p.name ASC LIMIT 1000";

      const [products] = await req.db.execute(query, params);

      res.json({
        success: true,
        products: products || [],
        order_store_id: orderStoreId,
      });
    } catch (error) {
      console.error("Error fetching available products:", error);
      res.status(500).json({
        success: false,
        message: "Failed to fetch products",
        error: error.message,
      });
    }
  },
);

module.exports = router;
