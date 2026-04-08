-- OrderDrop Database Performance Optimizations
-- This file contains additional indexes and optimizations for better query performance

USE orderdrop;

-- ==========================================
-- USERS TABLE INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX IF NOT EXISTS idx_users_user_type_active ON users(user_type, is_active);

-- ==========================================
-- STORES TABLE INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_stores_owner_id ON stores(owner_id);
CREATE INDEX IF NOT EXISTS idx_stores_created_at ON stores(created_at);
CREATE INDEX IF NOT EXISTS idx_stores_is_active_created ON stores(is_active, created_at);

-- ==========================================
-- PRODUCTS TABLE ADDITIONAL INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at);
CREATE INDEX IF NOT EXISTS idx_products_updated_at ON products(updated_at);
CREATE INDEX IF NOT EXISTS idx_products_store_category ON products(store_id, category_id);
CREATE INDEX IF NOT EXISTS idx_products_store_available ON products(store_id, is_available);

-- ==========================================
-- ORDERS TABLE INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_updated_at ON orders(updated_at);
CREATE INDEX IF NOT EXISTS idx_orders_rider_id ON orders(rider_id);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON orders(payment_status);
CREATE INDEX IF NOT EXISTS idx_orders_user_status ON orders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_store_status ON orders(store_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_created_status ON orders(created_at, status);

-- ==========================================
-- ORDER_ITEMS TABLE INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_order_items_created_at ON order_items(created_at);

-- ==========================================
-- RIDERS TABLE INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_riders_email ON riders(email);
CREATE INDEX IF NOT EXISTS idx_riders_created_at ON riders(created_at);

-- ==========================================
-- WALLET INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_wallets_balance ON wallets(balance);
CREATE INDEX IF NOT EXISTS idx_wallets_user_type ON wallets(user_type);

-- ==========================================
-- WALLET_TRANSACTIONS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_wt_balance_after ON wallet_transactions(balance_after);
CREATE INDEX IF NOT EXISTS idx_wt_reference ON wallet_transactions(reference_type, reference_id);

-- ==========================================
-- FINANCIAL_TRANSACTIONS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_ft_status ON financial_transactions(status);
CREATE INDEX IF NOT EXISTS idx_ft_related_entity ON financial_transactions(related_entity_type, related_entity_id);
CREATE INDEX IF NOT EXISTS idx_ft_reference ON financial_transactions(reference_type, reference_id);

-- ==========================================
-- CASH_PAYMENT_VOUCHERS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_cpv_payee_id ON cash_payment_vouchers(payee_id);
CREATE INDEX IF NOT EXISTS idx_cpv_created_at ON cash_payment_vouchers(created_at);

-- ==========================================
-- CASH_RECEIPT_VOUCHERS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_crv_payer_id ON cash_receipt_vouchers(payer_id);
CREATE INDEX IF NOT EXISTS idx_crv_created_at ON cash_receipt_vouchers(created_at);

-- ==========================================
-- RIDER_CASH_MOVEMENTS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_rcm_created_at ON rider_cash_movements(created_at);
CREATE INDEX IF NOT EXISTS idx_rcm_status ON rider_cash_movements(status);

-- ==========================================
-- STORE_SETTLEMENTS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_ss_created_at ON store_settlements(created_at);

-- ==========================================
-- ADMIN_EXPENSES INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_ae_created_at ON admin_expenses(created_at);
CREATE INDEX IF NOT EXISTS idx_ae_submitted_by ON admin_expenses(submitted_by);

-- ==========================================
-- FINANCIAL_REPORTS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_fr_created_at ON financial_reports(created_at);
CREATE INDEX IF NOT EXISTS idx_fr_period ON financial_reports(period_from, period_to);

-- ==========================================
-- RIDERS_FUEL_HISTORY INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_rfh_created_at ON riders_fuel_history(created_at);
CREATE INDEX IF NOT EXISTS idx_rfh_entry_date ON riders_fuel_history(entry_date);

-- ==========================================
-- WALLET_TRANSFERS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_wt_sender_id ON wallet_transfers(sender_id);
CREATE INDEX IF NOT EXISTS idx_wt_recipient_id ON wallet_transfers(recipient_id);
CREATE INDEX IF NOT EXISTS idx_wt_status ON wallet_transfers(status);
CREATE INDEX IF NOT EXISTS idx_wt_created_at ON wallet_transfers(created_at);

-- ==========================================
-- SAVED_PAYMENT_METHODS INDEXES
-- ==========================================
CREATE INDEX IF NOT EXISTS idx_spm_is_active ON saved_payment_methods(is_active);
