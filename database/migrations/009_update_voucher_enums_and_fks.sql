-- Update ENUMs for Payee and Payer types
ALTER TABLE cash_payment_vouchers MODIFY COLUMN payee_type ENUM('store', 'rider', 'vendor', 'employee', 'expense', 'other') NOT NULL;
ALTER TABLE cash_receipt_vouchers MODIFY COLUMN payer_type ENUM('customer', 'store', 'rider', 'vendor', 'employee', 'expense', 'other') NOT NULL;

-- Remove Foreign Key constraints for payee_id and payer_id
-- Note: You may need to verify the exact constraint names if they differ.
-- Common names are cash_payment_vouchers_ibfk_1 and cash_receipt_vouchers_ibfk_1
-- If the following commands fail, check information_schema.key_column_usage for correct names.

-- Try to drop FKs (wrapped in stored procedure to handle if exists, or just direct command if we assume they exist)
-- Simple SQL approach:
ALTER TABLE cash_payment_vouchers DROP FOREIGN KEY cash_payment_vouchers_ibfk_1;
ALTER TABLE cash_receipt_vouchers DROP FOREIGN KEY cash_receipt_vouchers_ibfk_1;

-- Also drop the indexes if they were created implicitly for the FKs (optional, but good practice)
-- ALTER TABLE cash_payment_vouchers DROP INDEX payee_id;
-- ALTER TABLE cash_receipt_vouchers DROP INDEX payer_id;
