const express = require('express');
const { body, validationResult } = require('express-validator');
const { authenticateToken, requireAdmin } = require('../middleware/auth');
const { recordFinancialTransaction } = require('../utils/dbHelpers');

const router = express.Router();

function generateVoucherNumber(prefix, date = new Date()) {
    const dateStr = date.toISOString().split('T')[0].replace(/-/g, '');
    const randomStr = Math.random().toString(36).substring(2, 8).toUpperCase();
    return `${prefix}-${dateStr}-${randomStr}`;
}

router.use(authenticateToken);
router.use(requireAdmin);

router.get('/dashboard', async (req, res) => {
    try {
        const { period = 'today' } = req.query;
        let dateFilter = '';
        let dateParams = [];

        const today = new Date();
        
        if (period === 'today') {
            const startOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate());
            const endOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
            dateFilter = 'WHERE DATE(ft.created_at) = DATE(?)';
            dateParams = [startOfDay.toISOString().split('T')[0]];
        } else if (period === 'week') {
            const startOfWeek = new Date(today);
            startOfWeek.setDate(today.getDate() - today.getDay());
            const endOfWeek = new Date(startOfWeek);
            endOfWeek.setDate(startOfWeek.getDate() + 7);
            dateFilter = 'WHERE ft.created_at >= ? AND ft.created_at < ?';
            dateParams = [startOfWeek.toISOString(), endOfWeek.toISOString()];
        } else if (period === 'month') {
            const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);
            const endOfMonth = new Date(today.getFullYear(), today.getMonth() + 1, 1);
            dateFilter = 'WHERE YEAR(ft.created_at) = ? AND MONTH(ft.created_at) = ?';
            dateParams = [startOfMonth.getFullYear(), startOfMonth.getMonth() + 1];
        }

        const [transactions] = await req.db.execute(
            `SELECT transaction_type, SUM(amount) as total FROM financial_transactions ft ${dateFilter} GROUP BY transaction_type`,
            dateParams
        );

        let paymentVoucherFilter = '';
        let paymentVoucherParams = [];
        if (period === 'today') {
            paymentVoucherFilter = 'WHERE status = \'paid\' AND DATE(voucher_date) = DATE(?)';
            paymentVoucherParams = [dateParams[0]];
        } else if (period === 'week') {
            paymentVoucherFilter = 'WHERE status = \'paid\' AND voucher_date >= ? AND voucher_date < ?';
            paymentVoucherParams = dateParams;
        } else if (period === 'month') {
            paymentVoucherFilter = 'WHERE status = \'paid\' AND YEAR(voucher_date) = ? AND MONTH(voucher_date) = ?';
            paymentVoucherParams = dateParams;
        } else {
            paymentVoucherFilter = 'WHERE status = \'paid\'';
        }

        const [paymentVouchers] = await req.db.execute(
            `SELECT SUM(amount) as total FROM cash_payment_vouchers ${paymentVoucherFilter}`,
            paymentVoucherParams
        );

        let receiptVoucherFilter = '';
        let receiptVoucherParams = [];
        if (period === 'today') {
            receiptVoucherFilter = 'WHERE status = \'received\' AND DATE(voucher_date) = DATE(?)';
            receiptVoucherParams = [dateParams[0]];
        } else if (period === 'week') {
            receiptVoucherFilter = 'WHERE status = \'received\' AND voucher_date >= ? AND voucher_date < ?';
            receiptVoucherParams = dateParams;
        } else if (period === 'month') {
            receiptVoucherFilter = 'WHERE status = \'received\' AND YEAR(voucher_date) = ? AND MONTH(voucher_date) = ?';
            receiptVoucherParams = dateParams;
        } else {
            receiptVoucherFilter = 'WHERE status = \'received\'';
        }

        const [receiptVouchers] = await req.db.execute(
            `SELECT SUM(amount) as total FROM cash_receipt_vouchers ${receiptVoucherFilter}`,
            receiptVoucherParams
        );

        let riderCashFilter = '';
        let riderCashParams = [];
        if (period === 'today') {
            riderCashFilter = 'WHERE status = \'completed\' AND DATE(movement_date) = DATE(?)';
            riderCashParams = [dateParams[0]];
        } else if (period === 'week') {
            riderCashFilter = 'WHERE status = \'completed\' AND movement_date >= ? AND movement_date < ?';
            riderCashParams = dateParams;
        } else if (period === 'month') {
            riderCashFilter = 'WHERE status = \'completed\' AND YEAR(movement_date) = ? AND MONTH(movement_date) = ?';
            riderCashParams = dateParams;
        } else {
            riderCashFilter = 'WHERE status = \'completed\'';
        }

        const [riderCash] = await req.db.execute(
            `SELECT movement_type, SUM(amount) as total FROM rider_cash_movements rcm ${riderCashFilter} GROUP BY movement_type`,
            riderCashParams
        );

        const stats = {
            income: 0,
            expense: 0,
            settlement: 0,
            refund: 0,
            adjustment: 0,
            paymentVouchers: parseFloat(paymentVouchers[0]?.total || 0),
            receiptVouchers: parseFloat(receiptVouchers[0]?.total || 0),
            riderCashSubmitted: 0,
            riderCashAdvance: 0
        };

        transactions.forEach(t => {
            stats[t.transaction_type] = parseFloat(t.total || 0);
        });

        riderCash.forEach(rc => {
            if (rc.movement_type === 'cash_submission') {
                stats.riderCashSubmitted += parseFloat(rc.total || 0);
            } else if (rc.movement_type === 'advance') {
                stats.riderCashAdvance += parseFloat(rc.total || 0);
            }
        });

        stats.net_profit = stats.income - (stats.expense + stats.settlement + stats.refund);

        res.json({
            success: true,
            stats,
            period
        });
    } catch (error) {
        console.error('Error fetching financial dashboard:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch dashboard data',
            error: error.message
        });
    }
});

router.get('/transactions', async (req, res) => {
    try {
        const { type, status, page = 1, limit = 20 } = req.query;
        const offset = (parseInt(page) - 1) * parseInt(limit);

        let whereClause = 'WHERE 1=1';
        const params = [];

        if (type) {
            whereClause += ' AND transaction_type = ?';
            params.push(type);
        }
        if (status) {
            whereClause += ' AND status = ?';
            params.push(status);
        }

        const [transactions] = await req.db.execute(
            `SELECT ft.*, cu.first_name as created_by_name, au.first_name as approved_by_name
             FROM financial_transactions ft
             LEFT JOIN users cu ON ft.created_by = cu.id
             LEFT JOIN users au ON ft.approved_by = au.id
             ${whereClause}
             ORDER BY ft.created_at DESC
             LIMIT ? OFFSET ?`,
            [...params, parseInt(limit), offset]
        );

        const [countResult] = await req.db.execute(
            `SELECT COUNT(*) as total FROM financial_transactions ft ${whereClause}`,
            params
        );

        res.json({
            success: true,
            transactions,
            total: countResult[0]?.total || 0,
            page: parseInt(page),
            limit: parseInt(limit)
        });
    } catch (error) {
        console.error('Error fetching transactions:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch transactions',
            error: error.message
        });
    }
});

router.post('/transactions', [
    body('transaction_type').isIn(['income', 'expense', 'settlement', 'refund', 'adjustment']),
    body('amount').isFloat({ min: 0.01 }),
    body('payment_method').isIn(['cash', 'card', 'bank_transfer', 'wallet', 'check']),
    body('description').optional().trim()
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

        const { transaction_type, category, description, amount, payment_method, reference_type, reference_id, notes } = req.body;
        
        const transactionId = await recordFinancialTransaction(req.db, {
            transaction_type,
            category,
            description,
            amount,
            payment_method,
            reference_type,
            reference_id,
            notes,
            created_by: req.user.id
        });

        if (!transactionId) {
            throw new Error('Failed to record transaction');
        }

        // Get the transaction number for the response
        const [rows] = await req.db.execute('SELECT transaction_number FROM financial_transactions WHERE id = ?', [transactionId]);

        res.status(201).json({
            success: true,
            message: 'Transaction recorded successfully',
            transaction: {
                id: transactionId,
                transaction_number: rows[0]?.transaction_number
            }
        });
    } catch (error) {
        console.error('Error creating transaction:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to create transaction',
            error: error.message
        });
    }
});

router.get('/payment-vouchers', async (req, res) => {
    try {
        const { status, payment_method, page = 1, limit = 20 } = req.query;
        const offset = (parseInt(page) - 1) * parseInt(limit);

        let whereClause = 'WHERE 1=1';
        const params = [];

        if (status) {
            whereClause += ' AND status = ?';
            params.push(status);
        }

        if (payment_method) {
            if (payment_method === 'cash') {
                whereClause += ' AND payment_method = \'cash\'';
            } else if (payment_method === 'bank') {
                whereClause += ' AND (payment_method = \'bank_transfer\' OR payment_method = \'check\')';
            }
        }

        const [vouchers] = await req.db.execute(
            `SELECT cpv.*, pb.first_name as prepared_by_name, ab.first_name as approved_by_name, pib.first_name as paid_by_name
             FROM cash_payment_vouchers cpv
             LEFT JOIN users pb ON cpv.prepared_by = pb.id
             LEFT JOIN users ab ON cpv.approved_by = ab.id
             LEFT JOIN users pib ON cpv.paid_by = pib.id
             ${whereClause}
             ORDER BY cpv.voucher_date DESC
             LIMIT ? OFFSET ?`,
            [...params, parseInt(limit), offset]
        );

        const [countResult] = await req.db.execute(
            `SELECT COUNT(*) as total FROM cash_payment_vouchers ${whereClause}`,
            params
        );

        res.json({
            success: true,
            vouchers,
            total: countResult[0]?.total || 0,
            page: parseInt(page),
            limit: parseInt(limit)
        });
    } catch (error) {
        console.error('Error fetching payment vouchers:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch payment vouchers',
            error: error.message
        });
    }
});

router.post('/payment-vouchers', [
    body('payee_name').trim().notEmpty(),
    body('payee_type').isIn(['store', 'rider', 'vendor', 'employee', 'other']),
    body('amount').isFloat({ min: 0.01 }),
    body('payment_method').isIn(['cash', 'check', 'bank_transfer']),
    body('purpose').optional().trim()
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

        const { payee_name, payee_type, payee_id, amount, purpose, description, payment_method, check_number, bank_details } = req.body;
        const voucher_number = generateVoucherNumber('CPV');
        const voucher_date = new Date().toISOString().split('T')[0];

        const [result] = await req.db.execute(
            `INSERT INTO cash_payment_vouchers 
             (voucher_number, voucher_date, payee_name, payee_type, payee_id, amount, purpose, description, payment_method, check_number, bank_details, prepared_by, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft')`,
            [voucher_number, voucher_date, payee_name, payee_type, payee_id || null, amount, purpose || null, description || null, payment_method, check_number || null, bank_details || null, req.user.id]
        );

        res.status(201).json({
            success: true,
            message: 'Payment voucher created successfully',
            voucher: {
                id: result.insertId,
                voucher_number
            }
        });
    } catch (error) {
        console.error('Error creating payment voucher:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to create payment voucher',
            error: error.message
        });
    }
});

router.put('/payment-vouchers/:id', [
    body('amount').optional().isFloat({ min: 0.01 }),
    body('status').optional().isIn(['draft', 'pending', 'approved', 'paid', 'cancelled'])
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
        const { payee_name, amount, status, description } = req.body;

        // Get existing voucher data if we're marking it as paid
        let existingVoucher = null;
        if (status === 'paid') {
            const [rows] = await req.db.execute('SELECT * FROM cash_payment_vouchers WHERE id = ?', [id]);
            if (rows.length === 0) {
                return res.status(404).json({ success: false, message: 'Voucher not found' });
            }
            existingVoucher = rows[0];
            
            if (existingVoucher.status === 'paid') {
                return res.status(400).json({ success: false, message: 'Voucher is already marked as paid' });
            }
        }

        const updates = [];
        const params = [];

        if (payee_name) {
            updates.push('payee_name = ?');
            params.push(payee_name);
        }
        if (amount) {
            updates.push('amount = ?');
            params.push(amount);
        }
        if (status) {
            updates.push('status = ?');
            params.push(status);
            if (status === 'approved') {
                updates.push('approved_by = ?, approved_at = NOW()');
                params.push(req.user.id);
            } else if (status === 'paid') {
                updates.push('paid_by = ?, paid_at = NOW()');
                params.push(req.user.id);
            }
        }
        if (description) {
            updates.push('description = ?');
            params.push(description);
        }

        if (updates.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'No fields to update'
            });
        }

        params.push(id);

        await req.db.execute(
            `UPDATE cash_payment_vouchers SET ${updates.join(', ')} WHERE id = ?`,
            params
        );

        // Create financial transaction if status changed to paid
        if (status === 'paid' && existingVoucher) {
            const voucherAmount = amount || existingVoucher.amount;
            const voucherPayee = payee_name || existingVoucher.payee_name;
            const voucherDescription = description || existingVoucher.description || existingVoucher.purpose || 'Payment via voucher';

            await recordFinancialTransaction(req.db, {
                transaction_type: 'expense',
                category: 'payment',
                description: `Payment to ${voucherPayee}: ${voucherDescription}`,
                amount: voucherAmount,
                payment_method: existingVoucher.payment_method,
                related_entity_type: existingVoucher.payee_type,
                related_entity_id: existingVoucher.payee_id,
                reference_type: 'payment_voucher',
                reference_id: existingVoucher.voucher_number,
                created_by: req.user.id
            });
        }

        res.json({
            success: true,
            message: 'Payment voucher updated successfully'
        });
    } catch (error) {
        console.error('Error updating payment voucher:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update payment voucher',
            error: error.message
        });
    }
});

router.get('/receipt-vouchers', async (req, res) => {
    try {
        const { status, payment_method, page = 1, limit = 20 } = req.query;
        const offset = (parseInt(page) - 1) * parseInt(limit);

        let whereClause = 'WHERE 1=1';
        const params = [];

        if (status) {
            whereClause += ' AND status = ?';
            params.push(status);
        }

        if (payment_method) {
            if (payment_method === 'cash') {
                whereClause += ' AND payment_method = \'cash\'';
            } else if (payment_method === 'bank') {
                whereClause += ' AND (payment_method = \'bank_transfer\' OR payment_method = \'check\')';
            }
        }

        const [vouchers] = await req.db.execute(
            `SELECT crv.*, pb.first_name as prepared_by_name, ab.first_name as approved_by_name, rb.first_name as received_by_name
             FROM cash_receipt_vouchers crv
             LEFT JOIN users pb ON crv.prepared_by = pb.id
             LEFT JOIN users ab ON crv.approved_by = ab.id
             LEFT JOIN users rb ON crv.received_by = rb.id
             ${whereClause}
             ORDER BY crv.voucher_date DESC
             LIMIT ? OFFSET ?`,
            [...params, parseInt(limit), offset]
        );

        const [countResult] = await req.db.execute(
            `SELECT COUNT(*) as total FROM cash_receipt_vouchers ${whereClause}`,
            params
        );

        res.json({
            success: true,
            vouchers,
            total: countResult[0]?.total || 0,
            page: parseInt(page),
            limit: parseInt(limit)
        });
    } catch (error) {
        console.error('Error fetching receipt vouchers:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch receipt vouchers',
            error: error.message
        });
    }
});

router.post('/receipt-vouchers', [
    body('payer_name').trim().notEmpty(),
    body('payer_type').isIn(['customer', 'store', 'vendor', 'other']),
    body('amount').isFloat({ min: 0.01 }),
    body('payment_method').isIn(['cash', 'check', 'bank_transfer']),
    body('description').optional().trim()
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

        const { payer_name, payer_type, payer_id, amount, description, details, payment_method, check_number, bank_details } = req.body;
        const voucher_number = generateVoucherNumber('CRV');
        const voucher_date = new Date().toISOString().split('T')[0];

        const [result] = await req.db.execute(
            `INSERT INTO cash_receipt_vouchers 
             (voucher_number, voucher_date, payer_name, payer_type, payer_id, amount, description, details, payment_method, check_number, bank_details, prepared_by, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'draft')`,
            [voucher_number, voucher_date, payer_name, payer_type, payer_id || null, amount, description || null, details || null, payment_method, check_number || null, bank_details || null, req.user.id]
        );

        res.status(201).json({
            success: true,
            message: 'Receipt voucher created successfully',
            voucher: {
                id: result.insertId,
                voucher_number
            }
        });
    } catch (error) {
        console.error('Error creating receipt voucher:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to create receipt voucher',
            error: error.message
        });
    }
});

router.put('/receipt-vouchers/:id', [
    body('amount').optional().isFloat({ min: 0.01 }),
    body('status').optional().isIn(['draft', 'pending', 'approved', 'received', 'cancelled'])
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
        const { payer_name, amount, status, description } = req.body;

        // Get existing voucher data if we're marking it as received
        let existingVoucher = null;
        if (status === 'received') {
            const [rows] = await req.db.execute('SELECT * FROM cash_receipt_vouchers WHERE id = ?', [id]);
            if (rows.length === 0) {
                return res.status(404).json({ success: false, message: 'Voucher not found' });
            }
            existingVoucher = rows[0];
            
            if (existingVoucher.status === 'received') {
                return res.status(400).json({ success: false, message: 'Voucher is already marked as received' });
            }
        }

        const updates = [];
        const params = [];

        if (payer_name) {
            updates.push('payer_name = ?');
            params.push(payer_name);
        }
        if (amount) {
            updates.push('amount = ?');
            params.push(amount);
        }
        if (status) {
            updates.push('status = ?');
            params.push(status);
            if (status === 'approved') {
                updates.push('approved_by = ?, approved_at = NOW()');
                params.push(req.user.id);
            } else if (status === 'received') {
                updates.push('received_by = ?, received_at = NOW()');
                params.push(req.user.id);
            }
        }
        if (description) {
            updates.push('description = ?');
            params.push(description);
        }

        if (updates.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'No fields to update'
            });
        }

        params.push(id);

        await req.db.execute(
            `UPDATE cash_receipt_vouchers SET ${updates.join(', ')} WHERE id = ?`,
            params
        );

        // Create financial transaction if status changed to received
        if (status === 'received' && existingVoucher) {
            const voucherAmount = amount || existingVoucher.amount;
            const voucherPayer = payer_name || existingVoucher.payer_name;
            const voucherDescription = description || existingVoucher.description || 'Receipt via voucher';

            await recordFinancialTransaction(req.db, {
                transaction_type: 'income',
                category: 'receipt',
                description: `Receipt from ${voucherPayer}: ${voucherDescription}`,
                amount: voucherAmount,
                payment_method: existingVoucher.payment_method,
                related_entity_type: existingVoucher.payer_type,
                related_entity_id: existingVoucher.payer_id,
                reference_type: 'receipt_voucher',
                reference_id: existingVoucher.voucher_number,
                created_by: req.user.id
            });
        }

        res.json({
            success: true,
            message: 'Receipt voucher updated successfully'
        });
    } catch (error) {
        console.error('Error updating receipt voucher:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update receipt voucher',
            error: error.message
        });
    }
});

router.get('/rider-cash', async (req, res) => {
    try {
        const { rider_id, type, status, page = 1, limit = 20 } = req.query;
        const offset = (parseInt(page) - 1) * parseInt(limit);

        let whereClause = 'WHERE 1=1';
        const params = [];

        if (rider_id) {
            whereClause += ' AND rcm.rider_id = ?';
            params.push(rider_id);
        }
        if (type) {
            whereClause += ' AND rcm.movement_type = ?';
            params.push(type);
        }
        if (status) {
            whereClause += ' AND rcm.status = ?';
            params.push(status);
        }

        // Only show movements for active riders
        whereClause += ' AND r.is_active = true';

        const [movements] = await req.db.execute(
            `SELECT rcm.*, r.first_name, r.last_name, rb.first_name as recorded_by_name, ab.first_name as approved_by_name
             FROM rider_cash_movements rcm
             LEFT JOIN riders r ON rcm.rider_id = r.id
             LEFT JOIN users rb ON rcm.recorded_by = rb.id
             LEFT JOIN users ab ON rcm.approved_by = ab.id
             ${whereClause}
             ORDER BY rcm.movement_date DESC
             LIMIT ? OFFSET ?`,
            [...params, parseInt(limit), offset]
        );

        const [countResult] = await req.db.execute(
            `SELECT COUNT(*) as total FROM rider_cash_movements rcm
             LEFT JOIN riders r ON rcm.rider_id = r.id
             ${whereClause}`,
            params
        );

        res.json({
            success: true,
            movements,
            total: countResult[0]?.total || 0,
            page: parseInt(page),
            limit: parseInt(limit)
        });
    } catch (error) {
        console.error('Error fetching rider cash movements:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch rider cash movements',
            error: error.message
        });
    }
});

// Helper function to get or create rider wallet
async function getOrCreateRiderWallet(db, riderId) {
    const [wallets] = await db.execute(
        `SELECT id, balance, total_credited, total_spent FROM wallets WHERE rider_id = ?`,
        [riderId]
    );

    if (!wallets.length) {
        await db.execute(
            'INSERT INTO wallets (rider_id, user_type, balance) VALUES (?, ?, ?)',
            [riderId, 'rider', 0]
        );
        
        const [newWallet] = await db.execute(
            'SELECT id, balance, total_credited, total_spent FROM wallets WHERE rider_id = ?',
            [riderId]
        );
        return newWallet[0];
    }
    return wallets[0];
}

// Helper function to record wallet transaction and update balance
async function recordRiderWalletTransaction(db, riderId, type, amount, description, movementId, movementType) {
    const wallet = await getOrCreateRiderWallet(db, riderId);
    const newBalance = type === 'credit' 
        ? parseFloat(wallet.balance || 0) + parseFloat(amount)
        : parseFloat(wallet.balance || 0) - parseFloat(amount);

    // Update wallet balance
    if (type === 'credit') {
        await db.execute(
            'UPDATE wallets SET balance = ?, total_credited = total_credited + ? WHERE id = ?',
            [newBalance, amount, wallet.id]
        );
    } else {
        await db.execute(
            'UPDATE wallets SET balance = ?, total_spent = total_spent + ? WHERE id = ?',
            [newBalance, amount, wallet.id]
        );
    }

    // Record wallet transaction
    await db.execute(
        `INSERT INTO wallet_transactions 
         (wallet_id, type, amount, description, reference_type, reference_id, balance_after) 
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [wallet.id, type, amount, description, 'rider_cash_movement', movementId, newBalance]
    );

    return { walletId: wallet.id, newBalance };
}

router.post('/rider-cash', [
    body('rider_id').isInt({ min: 1 }),
    body('movement_type').isIn(['cash_collection', 'cash_submission', 'advance', 'settlement', 'adjustment']),
    body('amount').isFloat({ min: 0.01 }),
    body('description').optional().trim()
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

        const { rider_id, movement_type, amount, description, reference_type, reference_id, notes } = req.body;
        const movement_number = generateVoucherNumber('RCM');
        const movement_date = new Date().toISOString().split('T')[0];

        const [result] = await req.db.execute(
            `INSERT INTO rider_cash_movements 
             (movement_number, rider_id, movement_date, movement_type, amount, description, reference_type, reference_id, recorded_by, notes, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
            [movement_number, rider_id, movement_date, movement_type, amount, description || null, reference_type || null, reference_id || null, req.user.id, notes || null]
        );

        // Auto-update wallet for advances (debit to rider wallet as they now owe the company)
        if (movement_type === 'advance') {
            await recordRiderWalletTransaction(
                req.db, 
                rider_id, 
                'debit', 
                amount, 
                `Cash advance via ${movement_number}`, 
                result.insertId,
                movement_type
            );
        }
        // Auto-update wallet for adjustments (could be credit or debit)
        else if (movement_type === 'adjustment' && parseFloat(amount) > 0) {
            await recordRiderWalletTransaction(
                req.db, 
                rider_id, 
                'credit', 
                amount, 
                `Adjustment credit via ${movement_number}`, 
                result.insertId,
                movement_type
            );
        }

        res.status(201).json({
            success: true,
            message: 'Rider cash movement recorded successfully',
            movement: {
                id: result.insertId,
                movement_number
            }
        });
    } catch (error) {
        console.error('Error creating rider cash movement:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to record rider cash movement',
            error: error.message
        });
    }
});

router.put('/rider-cash/:id', [
    body('status').optional().isIn(['pending', 'completed', 'approved', 'cancelled'])
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
        const { status, amount, description } = req.body;

        // Get current movement to check status transition
        const [movements] = await req.db.execute(
            'SELECT * FROM rider_cash_movements WHERE id = ?',
            [id]
        );

        if (!movements.length) {
            return res.status(404).json({
                success: false,
                message: 'Movement not found'
            });
        }

        const movement = movements[0];
        const updates = [];
        const params = [];

        if (amount && amount !== movement.amount) {
            updates.push('amount = ?');
            params.push(amount);
        }
        if (description !== undefined) {
            updates.push('description = ?');
            params.push(description);
        }
        if (status && status !== movement.status) {
            // Validate status transitions
            if (movement.status === 'approved' && status !== 'cancelled') {
                return res.status(400).json({
                    success: false,
                    message: 'Cannot change status of approved movement'
                });
            }

            updates.push('status = ?');
            params.push(status);
            
            if (status === 'approved') {
                updates.push('approved_by = ?, approved_at = NOW()');
                params.push(req.user.id);

                // Handle wallet updates and financial transactions based on movement type
                const effectiveAmount = amount || movement.amount;
                let transactionType = null;
                let descriptionPrefix = '';

                if (movement.movement_type === 'cash_submission') {
                    // Credit to rider wallet when cash submission is approved (reduces debt)
                    await recordRiderWalletTransaction(
                        req.db,
                        movement.rider_id,
                        'credit',
                        effectiveAmount,
                        `Cash submission via ${movement.movement_number}`,
                        movement.id,
                        movement.movement_type
                    );
                    // This is clearing a receivable, not new income, but we'll record it as adjustment
                    transactionType = 'adjustment';
                    descriptionPrefix = 'Rider Cash Submission';
                } else if (movement.movement_type === 'settlement') {
                    // Credit to rider wallet for settlements (earnings)
                    await recordRiderWalletTransaction(
                        req.db,
                        movement.rider_id,
                        'credit',
                        effectiveAmount,
                        `Settlement via ${movement.movement_number}`,
                        movement.id,
                        movement.movement_type
                    );
                    // Rider settlement is an expense/payout for the platform
                    transactionType = 'settlement';
                    descriptionPrefix = 'Rider Settlement';
                } else if (movement.movement_type === 'cash_collection') {
                    // Debit from rider wallet for cash collections (rider collected from customer)
                    // ONLY if not already handled by orders route
                    if (movement.reference_type !== 'order') {
                        await recordRiderWalletTransaction(
                            req.db,
                            movement.rider_id,
                            'debit',
                            effectiveAmount,
                            `Cash collection via ${movement.movement_number}`,
                            movement.id,
                            movement.movement_type
                        );
                    }
                    // Internal movement, already recorded as income/receivable at order time
                } else if (movement.movement_type === 'advance') {
                    // Advances are already debited on POST
                    transactionType = 'expense';
                    descriptionPrefix = 'Rider Advance';
                }

                // Create financial transaction if applicable
                if (transactionType) {
                    const [riderRows] = await req.db.execute('SELECT first_name, last_name FROM riders WHERE id = ?', [movement.rider_id]);
                    const riderName = riderRows.length > 0 ? `${riderRows[0].first_name} ${riderRows[0].last_name}` : `Rider #${movement.rider_id}`;

                    await recordFinancialTransaction(req.db, {
                        transaction_type: transactionType,
                        category: 'rider_cash',
                        description: `${descriptionPrefix} - ${riderName}: ${movement.description || 'Processed'}`,
                        amount: effectiveAmount,
                        payment_method: 'cash',
                        related_entity_type: 'rider',
                        related_entity_id: movement.rider_id,
                        reference_type: 'rider_cash_movement',
                        reference_id: movement.id,
                        created_by: req.user.id
                    });
                }
            }
        }

        if (updates.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'No fields to update'
            });
        }

        params.push(id);

        await req.db.execute(
            `UPDATE rider_cash_movements SET ${updates.join(', ')} WHERE id = ?`,
            params
        );

        res.json({
            success: true,
            message: 'Rider cash movement updated successfully'
        });
    } catch (error) {
        console.error('Error updating rider cash movement:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update rider cash movement',
            error: error.message
        });
    }
});

router.get('/store-settlements', async (req, res) => {
    try {
        const { store_id, status, page = 1, limit = 20 } = req.query;
        const offset = (parseInt(page) - 1) * parseInt(limit);

        let whereClause = 'WHERE 1=1';
        const params = [];

        if (store_id) {
            whereClause += ' AND store_id = ?';
            params.push(store_id);
        }
        if (status) {
            whereClause += ' AND status = ?';
            params.push(status);
        }

        const [settlements] = await req.db.execute(
            `SELECT ss.*, s.name as store_name, ab.first_name as approved_by_name, pb.first_name as paid_by_name
             FROM store_settlements ss
             LEFT JOIN stores s ON ss.store_id = s.id
             LEFT JOIN users ab ON ss.approved_by = ab.id
             LEFT JOIN users pb ON ss.paid_by = pb.id
             ${whereClause}
             ORDER BY ss.settlement_date DESC
             LIMIT ? OFFSET ?`,
            [...params, parseInt(limit), offset]
        );

        const [countResult] = await req.db.execute(
            `SELECT COUNT(*) as total FROM store_settlements ${whereClause}`,
            params
        );

        res.json({
            success: true,
            settlements,
            total: countResult[0]?.total || 0,
            page: parseInt(page),
            limit: parseInt(limit)
        });
    } catch (error) {
        console.error('Error fetching store settlements:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch store settlements',
            error: error.message
        });
    }
});

router.post('/store-settlements', [
    body('store_id').isInt({ min: 1 }),
    body('net_amount').isFloat({ min: 0 }),
    body('payment_method').isIn(['cash', 'check', 'bank_transfer'])
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

        const { store_id, period_from, period_to, total_orders_amount, commissions, deductions, net_amount, payment_method, notes } = req.body;
        const settlement_number = generateVoucherNumber('SS');
        const settlement_date = new Date().toISOString().split('T')[0];

        const [result] = await req.db.execute(
            `INSERT INTO store_settlements 
             (settlement_number, settlement_date, store_id, period_from, period_to, total_orders_amount, commissions, deductions, net_amount, payment_method, notes, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
            [settlement_number, settlement_date, store_id, period_from || null, period_to || null, total_orders_amount || 0, commissions || 0, deductions || 0, net_amount, payment_method, notes || null]
        );

        res.status(201).json({
            success: true,
            message: 'Store settlement created successfully',
            settlement: {
                id: result.insertId,
                settlement_number
            }
        });
    } catch (error) {
        console.error('Error creating store settlement:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to create store settlement',
            error: error.message
        });
    }
});

router.put('/store-settlements/:id', [
    body('status').optional().isIn(['pending', 'approved', 'paid', 'cancelled']),
    body('net_amount').optional().isFloat({ min: 0 })
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
        const { status, net_amount, notes } = req.body;

        // Get existing settlement data if we're marking it as paid
        let existingSettlement = null;
        if (status === 'paid') {
            const [rows] = await req.db.execute('SELECT * FROM store_settlements WHERE id = ?', [id]);
            if (rows.length === 0) {
                return res.status(404).json({ success: false, message: 'Settlement not found' });
            }
            existingSettlement = rows[0];
            
            if (existingSettlement.status === 'paid') {
                return res.status(400).json({ success: false, message: 'Settlement is already marked as paid' });
            }
        }

        const updates = [];
        const params = [];

        if (net_amount) {
            updates.push('net_amount = ?');
            params.push(net_amount);
        }
        if (status) {
            updates.push('status = ?');
            params.push(status);
            if (status === 'approved') {
                updates.push('approved_by = ?, approved_at = NOW()');
                params.push(req.user.id);
            } else if (status === 'paid') {
                updates.push('paid_by = ?, paid_at = NOW()');
                params.push(req.user.id);
            }
        }
        if (notes) {
            updates.push('notes = ?');
            params.push(notes);
        }

        if (updates.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'No fields to update'
            });
        }

        params.push(id);

        await req.db.execute(
            `UPDATE store_settlements SET ${updates.join(', ')} WHERE id = ?`,
            params
        );

        // Create financial transaction if status changed to paid
        if (status === 'paid' && existingSettlement) {
            const settlementAmount = net_amount || existingSettlement.net_amount;
            const [storeRows] = await req.db.execute('SELECT name FROM stores WHERE id = ?', [existingSettlement.store_id]);
            const storeName = storeRows.length > 0 ? storeRows[0].name : `Store #${existingSettlement.store_id}`;

            await recordFinancialTransaction(req.db, {
                transaction_type: 'settlement',
                category: 'store_settlement',
                description: `Settlement for ${storeName}: ${existingSettlement.settlement_number}`,
                amount: settlementAmount,
                payment_method: existingSettlement.payment_method,
                related_entity_type: 'store',
                related_entity_id: existingSettlement.store_id,
                reference_type: 'store_settlement',
                reference_id: existingSettlement.settlement_number,
                created_by: req.user.id
            });
        }

        res.json({
            success: true,
            message: 'Store settlement updated successfully'
        });
    } catch (error) {
        console.error('Error updating store settlement:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update store settlement',
            error: error.message
        });
    }
});

router.get('/expenses/categories', async (req, res) => {
    try {
        const [categories] = await req.db.execute('SELECT DISTINCT category FROM admin_expenses ORDER BY category');
        res.json({ success: true, categories: categories.map(c => c.category) });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

router.get('/expenses', async (req, res) => {
    try {
        const { category, status, page = 1, limit = 20 } = req.query;
        const offset = (parseInt(page) - 1) * parseInt(limit);

        let whereClause = 'WHERE 1=1';
        const params = [];

        if (category) {
            whereClause += ' AND category = ?';
            params.push(category);
        }
        if (status) {
            whereClause += ' AND status = ?';
            params.push(status);
        }

        const [expenses] = await req.db.execute(
            `SELECT ae.*, sb.first_name as submitted_by_name, ab.first_name as approved_by_name
             FROM admin_expenses ae
             LEFT JOIN users sb ON ae.submitted_by = sb.id
             LEFT JOIN users ab ON ae.approved_by = ab.id
             ${whereClause}
             ORDER BY ae.expense_date DESC
             LIMIT ? OFFSET ?`,
            [...params, parseInt(limit), offset]
        );

        const [countResult] = await req.db.execute(
            `SELECT COUNT(*) as total FROM admin_expenses ${whereClause}`,
            params
        );

        res.json({
            success: true,
            expenses,
            total: countResult[0]?.total || 0,
            page: parseInt(page),
            limit: parseInt(limit)
        });
    } catch (error) {
        console.error('Error fetching expenses:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch expenses',
            error: error.message
        });
    }
});

router.post('/expenses', [
    body('category').trim().notEmpty(),
    body('amount').isFloat({ min: 0.01 }),
    body('payment_method').isIn(['cash', 'card', 'check', 'bank_transfer']),
    body('description').optional().trim()
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

        const { category, description, amount, payment_method, vendor_name, receipt_number, notes } = req.body;
        const expense_number = generateVoucherNumber('EXP');
        const expense_date = new Date().toISOString().split('T')[0];

        const [result] = await req.db.execute(
            `INSERT INTO admin_expenses 
             (expense_number, expense_date, category, description, amount, payment_method, vendor_name, receipt_number, notes, submitted_by, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
            [expense_number, expense_date, category, description || null, amount, payment_method, vendor_name || null, receipt_number || null, notes || null, req.user.id]
        );

        res.status(201).json({
            success: true,
            message: 'Expense recorded successfully',
            expense: {
                id: result.insertId,
                expense_number
            }
        });
    } catch (error) {
        console.error('Error creating expense:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to create expense',
            error: error.message
        });
    }
});

router.put('/expenses/:id', [
    body('status').optional().isIn(['pending', 'approved', 'paid', 'rejected']),
    body('amount').optional().isFloat({ min: 0.01 })
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
        const { status, amount, notes } = req.body;

        // Get existing expense data if we're marking it as paid
        let existingExpense = null;
        if (status === 'paid') {
            const [rows] = await req.db.execute('SELECT * FROM admin_expenses WHERE id = ?', [id]);
            if (rows.length === 0) {
                return res.status(404).json({ success: false, message: 'Expense not found' });
            }
            existingExpense = rows[0];
            
            if (existingExpense.status === 'paid') {
                return res.status(400).json({ success: false, message: 'Expense is already marked as paid' });
            }
        }

        const updates = [];
        const params = [];

        if (amount) {
            updates.push('amount = ?');
            params.push(amount);
        }
        if (status) {
            updates.push('status = ?');
            params.push(status);
            if (status === 'approved') {
                updates.push('approved_by = ?, approved_at = NOW()');
                params.push(req.user.id);
            }
        }
        if (notes) {
            updates.push('notes = ?');
            params.push(notes);
        }

        if (updates.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'No fields to update'
            });
        }

        params.push(id);

        await req.db.execute(
            `UPDATE admin_expenses SET ${updates.join(', ')} WHERE id = ?`,
            params
        );

        // Create financial transaction if status changed to paid
        if (status === 'paid' && existingExpense) {
            const expenseAmount = amount || existingExpense.amount;
            const expenseDescription = existingExpense.description || 'Admin Expense';

            await recordFinancialTransaction(req.db, {
                transaction_type: 'expense',
                category: existingExpense.category,
                description: `Expense: ${existingExpense.category} - ${expenseDescription}`,
                amount: expenseAmount,
                payment_method: existingExpense.payment_method,
                related_entity_type: 'admin_expense',
                related_entity_id: existingExpense.id,
                reference_type: 'admin_expense',
                reference_id: existingExpense.expense_number,
                created_by: req.user.id
            });
        }

        res.json({
            success: true,
            message: 'Expense updated successfully'
        });
    } catch (error) {
        console.error('Error updating expense:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update expense',
            error: error.message
        });
    }
});

router.get('/reports', async (req, res) => {
    try {
        const { type, period_from, period_to } = req.query;

        let whereClause = 'WHERE 1=1';
        const params = [];

        if (type) {
            whereClause += ' AND report_type = ?';
            params.push(type);
        }
        if (period_from) {
            whereClause += ' AND period_from >= ?';
            params.push(period_from);
        }
        if (period_to) {
            whereClause += ' AND period_to <= ?';
            params.push(period_to);
        }

        const [reports] = await req.db.execute(
            `SELECT fr.*, u.first_name as generated_by_name
             FROM financial_reports fr
             LEFT JOIN users u ON fr.generated_by = u.id
             ${whereClause}
             ORDER BY fr.created_at DESC`,
            params
        );

        res.json({
            success: true,
            reports
        });
    } catch (error) {
        console.error('Error fetching reports:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch reports',
            error: error.message
        });
    }
});

router.post('/reports/generate', [
    body('report_type').isIn(['daily_summary', 'weekly_summary', 'monthly_summary', 'store_settlement', 'rider_cash_report', 'expense_report', 'general_voucher', 'store_financials', 'custom']),
    body('period_from').optional().isISO8601(),
    body('period_to').optional().isISO8601()
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

        const { report_type, period_from, period_to } = req.body;
        const report_number = generateVoucherNumber('RPT');

        let reportData = {};
        let total_income = 0, total_expense = 0, total_settlements = 0, total_refunds = 0, total_adjustments = 0;

        const dateFilterFT = period_from && period_to ? 'AND ft.created_at BETWEEN ? AND ?' : '';
        const dateParams = period_from && period_to ? [period_from, period_to] : [];

        // Base financial summary (always useful)
        const [transactions] = await req.db.execute(
            `SELECT transaction_type, SUM(amount) as total FROM financial_transactions ft WHERE 1=1 ${dateFilterFT} GROUP BY transaction_type`,
            dateParams
        );

        transactions.forEach(t => {
            const amount = parseFloat(t.total || 0);
            switch (t.transaction_type) {
                case 'income': total_income += amount; break;
                case 'expense': total_expense += amount; break;
                case 'settlement': total_settlements += amount; break;
                case 'refund': total_refunds += amount; break;
                case 'adjustment': total_adjustments += amount; break;
            }
        });

        if (report_type === 'rider_cash_report') {
            const riderDateFilter = period_from && period_to ? 'AND movement_date BETWEEN ? AND ?' : '';
            const [movements] = await req.db.execute(
                `SELECT rcm.*, r.first_name, r.last_name 
                 FROM rider_cash_movements rcm
                 JOIN riders r ON rcm.rider_id = r.id
                 WHERE 1=1 ${riderDateFilter}
                 ORDER BY movement_date DESC`,
                dateParams
            );
            
            const [summary] = await req.db.execute(
                `SELECT movement_type, SUM(amount) as total 
                 FROM rider_cash_movements 
                 WHERE 1=1 ${riderDateFilter} 
                 GROUP BY movement_type`,
                dateParams
            );

            reportData = {
                type: 'rider_cash',
                movements,
                summary: summary.reduce((acc, curr) => {
                    acc[curr.movement_type] = curr.total;
                    return acc;
                }, {})
            };
        } else if (report_type === 'general_voucher') {
            const jnvDateFilter = period_from && period_to ? 'AND voucher_date BETWEEN ? AND ?' : '';
            const [vouchers] = await req.db.execute(
                `SELECT jnv.*, u.first_name as prepared_by_name 
                 FROM journal_vouchers jnv
                 LEFT JOIN users u ON jnv.prepared_by = u.id
                 WHERE 1=1 ${jnvDateFilter}
                 ORDER BY voucher_date DESC`,
                dateParams
            );

            // Get entries for these vouchers
            for (let v of vouchers) {
                const [entries] = await req.db.execute(
                    `SELECT * FROM journal_voucher_entries WHERE jnv_id = ?`,
                    [v.id]
                );
                v.entries = entries;
            }

            reportData = {
                type: 'general_voucher',
                vouchers
            };
        } else if (report_type === 'store_financials') {
            const orderDateFilter = period_from && period_to ? 'AND o.created_at BETWEEN ? AND ?' : '';
            const [financials] = await req.db.execute(
                `SELECT 
                    s.name as store_name,
                    SUM(oi.quantity * oi.price) as total_sales,
                    SUM(oi.quantity * p.cost_price) as total_cost,
                    SUM(oi.quantity * (oi.price - p.cost_price)) as estimated_profit
                 FROM order_items oi
                 JOIN orders o ON oi.order_id = o.id
                 JOIN products p ON oi.product_id = p.id
                 JOIN stores s ON oi.store_id = s.id
                 WHERE o.status = 'delivered' ${orderDateFilter}
                 GROUP BY s.id, s.name`,
                dateParams
            );

            reportData = {
                type: 'store_financials',
                stores: financials,
                overall: financials.reduce((acc, curr) => {
                    acc.total_sales += parseFloat(curr.total_sales || 0);
                    acc.total_cost += parseFloat(curr.total_cost || 0);
                    acc.total_profit += parseFloat(curr.estimated_profit || 0);
                    return acc;
                }, { total_sales: 0, total_cost: 0, total_profit: 0 })
            };
        } else {
            reportData = {
                transactions: transactions.map(t => ({ type: t.transaction_type, total: t.total })),
                summary: { 
                    total_income, 
                    total_expense, 
                    total_settlements, 
                    total_refunds,
                    total_adjustments,
                    net_profit: total_income - total_expense - total_settlements - total_refunds
                }
            };
        }

        const net_profit = total_income - total_expense - total_settlements - total_refunds;

        const [result] = await req.db.execute(
            `INSERT INTO financial_reports 
             (report_number, report_type, period_from, period_to, total_income, total_expense, total_commissions, net_profit, data, generated_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                report_number, 
                report_type, 
                period_from || null, 
                period_to || null, 
                total_income, 
                total_expense + total_refunds, // Group refunds with expenses for legacy schema compatibility
                total_settlements, // Store settlements in total_commissions column
                net_profit, 
                JSON.stringify(reportData), 
                req.user.id
            ]
        );

        res.status(201).json({
            success: true,
            message: 'Report generated successfully',
            report: {
                id: result.insertId,
                report_number,
                total_income,
                total_expense,
                total_settlements,
                net_profit
            }
        });
    } catch (error) {
        console.error('Error generating report:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to generate report',
            error: error.message
        });
    }
});

// ===== CUSTOM REPORTS =====

// Rider Report
router.get('/reports/rider/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const { start_date, end_date } = req.query;
        let dateFilter = '';
        let params = [id];

        if (start_date && end_date) {
            dateFilter = ' AND created_at BETWEEN ? AND ?';
            params.push(start_date, end_date);
        }

        // i. Number of Orders (Delivered, Cancelled, Pending)
        const [orderStats] = await req.db.execute(
            `SELECT status, COUNT(*) as count FROM orders WHERE rider_id = ? ${dateFilter} GROUP BY status`,
            params
        );

        // ii. Reviews and Ratings (Placeholder as table doesn't exist yet, but checking stores for pattern)
        // For now returning default
        const ratings = { average: 0, total_reviews: 0 };

        // iv. Payment in Credit
        // Usually means orders paid via Card/Wallet where Rider gets credited in their wallet
        const [creditPayments] = await req.db.execute(
            `SELECT SUM(amount) as total FROM wallet_transactions wt
             JOIN wallets w ON wt.wallet_id = w.id
             WHERE w.rider_id = ? AND wt.type = 'credit' AND wt.reference_type = 'order' ${dateFilter.replace('created_at', 'wt.created_at')}`,
            params
        );

        // v. Kilometers Travelled
        const [kmStats] = await req.db.execute(
            `SELECT SUM(distance) as total_km FROM riders_fuel_history WHERE rider_id = ? ${dateFilter.replace('created_at', 'entry_date')}`,
            params
        );

        res.json({
            success: true,
            report: {
                rider_id: id,
                orders: orderStats,
                ratings,
                payment_in_credit: parseFloat(creditPayments[0]?.total || 0),
                km_travelled: parseFloat(kmStats[0]?.total_km || 0)
            }
        });
    } catch (error) {
        console.error('Error fetching rider report:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch rider report', error: error.message });
    }
});

// Store Report
router.get('/reports/store/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const { start_date, end_date } = req.query;
        let dateFilter = '';
        let params = [id];

        if (start_date && end_date) {
            dateFilter = ' AND created_at BETWEEN ? AND ?';
            params.push(start_date, end_date);
        }

        // i. Number of Purchases (Product-wise)
        const [productStats] = await req.db.execute(
            `SELECT p.name, SUM(oi.quantity) as total_quantity, SUM(oi.price * oi.quantity) as total_amount
             FROM order_items oi
             JOIN products p ON oi.product_id = p.id
             JOIN orders o ON oi.order_id = o.id
             WHERE oi.store_id = ? ${dateFilter.replace('created_at', 'o.created_at')}
             GROUP BY p.id, p.name`,
            params
        );

        // ii. Total Purchases after Less Discount
        const [totalStats] = await req.db.execute(
            `SELECT SUM(total_amount) as total_gross FROM orders WHERE store_id = ? AND status = 'delivered' ${dateFilter}`,
            params
        );

        res.json({
            success: true,
            report: {
                store_id: id,
                product_wise_purchases: productStats,
                total_purchases: parseFloat(totalStats[0]?.total_gross || 0)
            }
        });
    } catch (error) {
        console.error('Error fetching store report:', error);
        res.status(500).json({ success: false, message: 'Failed to fetch store report', error: error.message });
    }
});

// ===== JOURNAL VOUCHERS (JNV) =====

router.get('/journal-vouchers', async (req, res) => {
    try {
        const [vouchers] = await req.db.execute(
            `SELECT j.*, u.first_name as prepared_by_name FROM journal_vouchers j
             LEFT JOIN users u ON j.prepared_by = u.id ORDER BY j.voucher_date DESC`
        );
        res.json({ success: true, vouchers });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

router.get('/journal-vouchers/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const [vouchers] = await req.db.execute(
            `SELECT j.*, u.first_name as prepared_by_name, ab.first_name as approved_by_name 
             FROM journal_vouchers j
             LEFT JOIN users u ON j.prepared_by = u.id 
             LEFT JOIN users ab ON j.approved_by = ab.id
             WHERE j.id = ?`,
            [id]
        );

        if (vouchers.length === 0) {
            return res.status(404).json({ success: false, message: 'Journal Voucher not found' });
        }

        const [entries] = await req.db.execute(
            `SELECT * FROM journal_voucher_entries WHERE jnv_id = ?`,
            [id]
        );

        res.json({ success: true, voucher: vouchers[0], entries });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

router.post('/journal-vouchers', [
    body('voucher_date').isDate(),
    body('total_amount').isFloat({ min: 0 }),
    body('entries').isArray().isLength({ min: 2 })
], async (req, res) => {
    try {
        const errors = validationResult(req);
        if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });

        const { voucher_date, description, reference_number, total_amount, entries } = req.body;
        const voucher_number = generateVoucherNumber('JNV');

        const [result] = await req.db.execute(
            `INSERT INTO journal_vouchers (voucher_number, voucher_date, description, reference_number, total_amount, prepared_by)
             VALUES (?, ?, ?, ?, ?, ?)`,
            [voucher_number, voucher_date, description, reference_number, total_amount, req.user.id]
        );

        const jnv_id = result.insertId;

        for (const entry of entries) {
            await req.db.execute(
                `INSERT INTO journal_voucher_entries (jnv_id, account_name, entity_type, entity_id, entry_type, amount, description)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                [jnv_id, entry.account_name, entry.entity_type, entry.entity_id, entry.entry_type, entry.amount, entry.description]
            );
        }

        res.status(201).json({ success: true, message: 'Journal Voucher created successfully', voucher_number });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

router.post('/journal-vouchers/:id/post', async (req, res) => {
    try {
        const { id } = req.params;
        const [vouchers] = await req.db.execute('SELECT * FROM journal_vouchers WHERE id = ?', [id]);
        
        if (vouchers.length === 0) return res.status(404).json({ success: false, message: 'Voucher not found' });
        const voucher = vouchers[0];

        if (voucher.status !== 'draft') {
            return res.status(400).json({ success: false, message: `Cannot post voucher with status: ${voucher.status}` });
        }

        const [entries] = await req.db.execute('SELECT * FROM journal_voucher_entries WHERE jnv_id = ?', [id]);
        if (entries.length === 0) return res.status(400).json({ success: false, message: 'Voucher has no entries' });

        // Update voucher status
        await req.db.execute(
            'UPDATE journal_vouchers SET status = \'posted\', approved_by = ?, posted_at = NOW() WHERE id = ?',
            [req.user.id, id]
        );

        // Post each entry to the master ledger
        for (const entry of entries) {
            await recordFinancialTransaction(req.db, {
                transaction_type: 'adjustment',
                category: 'journal_entry',
                description: entry.description || voucher.description || `JNV Posting: ${entry.account_name}`,
                amount: entry.amount,
                payment_method: 'bank_transfer', // JNVs are usually non-cash/bank
                related_entity_type: entry.entity_type,
                related_entity_id: entry.entity_id,
                reference_type: 'journal_voucher_entry',
                reference_id: entry.id,
                created_by: req.user.id,
                notes: `Voucher: ${voucher.voucher_number} | Type: ${entry.entry_type.toUpperCase()}`
            });
        }

        res.json({ success: true, message: 'Journal Voucher posted successfully' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

router.put('/journal-vouchers/:id/cancel', async (req, res) => {
    try {
        const { id } = req.params;
        const [vouchers] = await req.db.execute('SELECT status FROM journal_vouchers WHERE id = ?', [id]);
        
        if (vouchers.length === 0) return res.status(404).json({ success: false, message: 'Voucher not found' });
        if (vouchers[0].status === 'posted') {
            return res.status(400).json({ success: false, message: 'Cannot cancel a posted voucher' });
        }

        await req.db.execute('UPDATE journal_vouchers SET status = \'cancelled\' WHERE id = ?', [id]);
        res.json({ success: true, message: 'Journal Voucher cancelled successfully' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Platform Summary Report
router.get('/reports/platform-summary', async (req, res) => {
    try {
        const { start_date, end_date } = req.query;
        let dateFilter = '';
        let params = [];

        if (start_date && end_date) {
            dateFilter = ' WHERE created_at BETWEEN ? AND ?';
            params.push(start_date, end_date);
        }

        const [orders] = await req.db.execute(
            `SELECT COUNT(*) as total_orders, SUM(total_amount) as gross_sales, SUM(delivery_fee) as total_delivery_fees 
             FROM orders ${dateFilter}`,
            params
        );

        const [stores] = await req.db.execute('SELECT COUNT(*) as active_stores FROM stores WHERE is_active = true');
        const [riders] = await req.db.execute('SELECT COUNT(*) as active_riders FROM riders WHERE is_active = true');
        const [users] = await req.db.execute('SELECT COUNT(*) as total_customers FROM users WHERE user_type = \'customer\'');

        res.json({
            success: true,
            report: {
                ...orders[0],
                active_stores: stores[0].active_stores,
                active_riders: riders[0].active_riders,
                total_customers: users[0].total_customers
            }
        });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Top Selling Products Report
router.get('/reports/top-products', async (req, res) => {
    try {
        const { limit = 10 } = req.query;
        const [products] = await req.db.execute(
            `SELECT p.name, s.name as store_name, SUM(oi.quantity) as total_sold, SUM(oi.price * oi.quantity) as total_revenue
             FROM order_items oi
             JOIN products p ON oi.product_id = p.id
             JOIN stores s ON p.store_id = s.id
             GROUP BY p.id, p.name, s.name
             ORDER BY total_sold DESC
             LIMIT ?`,
            [parseInt(limit)]
        );
        res.json({ success: true, products });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Rider Performance Ranking
router.get('/reports/rider-performance', async (req, res) => {
    try {
        const [riders] = await req.db.execute(
            `SELECT r.id, r.first_name, r.last_name, 
                    COUNT(o.id) as total_deliveries, 
                    SUM(o.total_amount) as total_cash_handled,
                    (SELECT SUM(distance) FROM riders_fuel_history WHERE rider_id = r.id) as total_km
             FROM riders r
             LEFT JOIN orders o ON r.id = o.rider_id AND o.status = 'delivered'
             GROUP BY r.id, r.first_name, r.last_name
             ORDER BY total_deliveries DESC`
        );
        res.json({ success: true, riders });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Store Performance Ranking
router.get('/reports/store-performance', async (req, res) => {
    try {
        const [stores] = await req.db.execute(
            `SELECT s.id, s.name, s.rating, 
                    COUNT(o.id) as total_orders, 
                    SUM(o.total_amount) as total_sales
             FROM stores s
             LEFT JOIN orders o ON s.id = o.store_id AND o.status = 'delivered'
             GROUP BY s.id, s.name, s.rating
             ORDER BY total_sales DESC`
        );
        res.json({ success: true, stores });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Cash Flow Analysis (Rider Collections vs Submissions)
router.get('/reports/cash-flow', async (req, res) => {
    try {
        const [collections] = await req.db.execute(
            `SELECT SUM(amount) as total FROM rider_cash_movements WHERE movement_type = 'cash_collection' AND status = 'completed'`
        );
        const [submissions] = await req.db.execute(
            `SELECT SUM(amount) as total FROM rider_cash_movements WHERE movement_type = 'cash_submission' AND status = 'completed'`
        );
        const [vouchers] = await req.db.execute(
            `SELECT SUM(amount) as total FROM cash_receipt_vouchers WHERE status = 'received'`
        );

        res.json({
            success: true,
            summary: {
                total_rider_collections: parseFloat(collections[0]?.total || 0),
                total_rider_submissions: parseFloat(submissions[0]?.total || 0),
                total_other_receipts: parseFloat(vouchers[0]?.total || 0),
                pending_with_riders: parseFloat(collections[0]?.total || 0) - parseFloat(submissions[0]?.total || 0)
            }
        });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Category Wise Sales Report
router.get('/reports/category-sales', async (req, res) => {
    try {
        const [categories] = await req.db.execute(
            `SELECT c.name, COUNT(oi.id) as items_sold, SUM(oi.price * oi.quantity) as revenue
             FROM order_items oi
             JOIN products p ON oi.product_id = p.id
             JOIN categories c ON p.category_id = c.id
             GROUP BY c.id, c.name
             ORDER BY revenue DESC`
        );
        res.json({ success: true, categories });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Detailed Rider Report
router.get('/reports/riders-detailed', async (req, res) => {
    try {
        const { start_date, end_date, rider_id } = req.query;
        let dateFilter = '';
        let riderFilter = '';
        let params = [];

        if (start_date && end_date) {
            dateFilter = ' AND o.created_at BETWEEN ? AND ?';
            params.push(`${start_date} 00:00:00`, `${end_date} 23:59:59`);
        }

        if (rider_id && rider_id !== 'all') {
            riderFilter = ' WHERE r.id = ?';
            params.push(rider_id);
        }

        const [riders] = await req.db.execute(
            `SELECT 
                r.id, 
                r.first_name, 
                r.last_name, 
                r.email, 
                r.phone,
                COUNT(o.id) as total_assigned,
                COUNT(CASE WHEN o.status = 'delivered' THEN 1 END) as total_delivered,
                COUNT(CASE WHEN o.status = 'cancelled' THEN 1 END) as total_cancelled,
                SUM(CASE WHEN o.status = 'delivered' THEN o.delivery_fee ELSE 0 END) as total_fees,
                COALESCE((SELECT SUM(amount) FROM rider_cash_movements WHERE rider_id = r.id AND movement_type = 'cash_collection' AND status = 'completed'), 0) as cash_collection,
                COALESCE((SELECT SUM(amount) FROM rider_cash_movements WHERE rider_id = r.id AND movement_type = 'cash_submission' AND status = 'completed'), 0) as cash_submission
            FROM riders r
            LEFT JOIN orders o ON r.id = o.rider_id ${dateFilter}
            ${riderFilter}
            GROUP BY r.id, r.first_name, r.last_name, r.email, r.phone
            ORDER BY total_delivered DESC`,
            params
        );
        res.json({ success: true, riders });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

// Detailed Store Report
router.get('/reports/stores-detailed', async (req, res) => {
    try {
        const { start_date, end_date, store_id } = req.query;
        let dateFilter = '';
        let storeFilter = '';
        let params = [];

        if (start_date && end_date) {
            dateFilter = ' AND o.created_at BETWEEN ? AND ?';
            params.push(`${start_date} 00:00:00`, `${end_date} 23:59:59`);
        }

        if (store_id && store_id !== 'all') {
            storeFilter = ' WHERE s.id = ?';
            params.push(store_id);
        }

        const [stores] = await req.db.execute(
            `SELECT 
                s.id, 
                s.name, 
                s.email, 
                s.phone,
                COUNT(DISTINCT o.id) as total_orders,
                SUM(CASE WHEN o.status = 'delivered' THEN oi.price * oi.quantity ELSE 0 END) as total_earnings,
                COALESCE((SELECT SUM(net_amount) FROM store_settlements WHERE store_id = s.id AND status = 'paid'), 0) as total_paid,
                COALESCE((SELECT SUM(oi2.price * oi2.quantity) FROM order_items oi2 JOIN orders o2 ON oi2.order_id = o2.id WHERE oi2.store_id = s.id AND o2.status = 'delivered'), 0) - COALESCE((SELECT SUM(net_amount) FROM store_settlements WHERE store_id = s.id AND status = 'paid'), 0) as pending_settlement
            FROM stores s
            LEFT JOIN order_items oi ON s.id = oi.store_id
            LEFT JOIN orders o ON oi.order_id = o.id ${dateFilter}
            ${storeFilter}
            GROUP BY s.id, s.name, s.email, s.phone
            ORDER BY total_earnings DESC`,
            params
        );
        res.json({ success: true, stores });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
});

module.exports = router;
