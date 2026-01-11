-- Add indexes for better query performance
ALTER TABLE riders ADD INDEX idx_riders_is_active (is_active);
ALTER TABLE stores ADD INDEX idx_stores_is_active (is_active);
ALTER TABLE products ADD INDEX idx_products_is_available (is_available);
ALTER TABLE products ADD INDEX idx_products_store_is_available (store_id, is_available);
ALTER TABLE order_items ADD INDEX idx_order_items_product_id (product_id);
ALTER TABLE order_items ADD INDEX idx_order_items_store_id (store_id);
