-- Migration to rename 'check' to 'cheque' in all financial tables

-- 1. Financial Transactions
ALTER TABLE financial_transactions 
MODIFY COLUMN payment_method ENUM('cash', 'card', 'bank_transfer', 'wallet', 'cheque') NOT NULL;

-- 2. Cash Payment Vouchers
ALTER TABLE cash_payment_vouchers 
MODIFY COLUMN payment_method ENUM('cash', 'cheque', 'bank_transfer') NOT NULL;
-- (Assuming cheque_number is already correct or was created as such, but if it was check_number, we would rename it. 
-- Schema said it was cheque_number, so we leave it or check if we need to rename)
-- Just in case it was check_number in a previous version:
-- ALTER TABLE cash_payment_vouchers CHANGE COLUMN check_number cheque_number VARCHAR(50);

-- 3. Cash Receipt Vouchers
ALTER TABLE cash_receipt_vouchers 
MODIFY COLUMN payment_method ENUM('cash', 'cheque', 'bank_transfer') NOT NULL;

ALTER TABLE cash_receipt_vouchers 
CHANGE COLUMN check_number cheque_number VARCHAR(50);

-- 4. Store Settlements
ALTER TABLE store_settlements 
MODIFY COLUMN payment_method ENUM('cash', 'cheque', 'bank_transfer') NOT NULL;

-- 5. Admin Expenses
ALTER TABLE admin_expenses 
MODIFY COLUMN payment_method ENUM('cash', 'card', 'cheque', 'bank_transfer') NOT NULL;
