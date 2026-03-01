let currentTransactions = [];
let currentPaymentVouchers = [];
let currentReceiptVouchers = [];
let currentRiderCash = [];
let currentStoreSettlements = [];
let currentExpenses = [];
let currentReports = [];
let currentJournalVouchers = [];
let lastRiderData = [];
let lastStoreData = [];

const financialModalIds = ['paymentVoucherModal', 'receiptVoucherModal', 'transactionModal', 'riderCashModal', 'storeSettlementModal', 'expenseModal', 'journalVoucherModal'];
const formChangedState = {};

function openModal(modalId) {
    document.getElementById(modalId).classList.add('show');
    
    // Initialize listeners when the settlement modal opens
    if (modalId === 'storeSettlementModal') {
        // We delay slightly to ensure DOM is ready/visible if needed, though usually unnecessary
        setTimeout(setupStoreSettlementListeners, 100);
    }
}

function closeModal(modalId) {
    const isFiancialModal = financialModalIds.includes(modalId);
    if (isFiancialModal && formChangedState[modalId]) {
        const confirmed = confirm('You have unsaved changes. Are you sure you want to close without saving?');
        if (!confirmed) return;
    }
    document.getElementById(modalId).classList.remove('show');
    if (isFiancialModal) formChangedState[modalId] = false;
}

function trackFormChanges(formId, modalId) {
    const form = document.getElementById(formId);
    if (!form) return;
    
    form.addEventListener('change', () => {
        formChangedState[modalId] = true;
    });
    
    form.addEventListener('input', () => {
        formChangedState[modalId] = true;
    });
}

async function loadJournalVouchers() {
    try {
        const status = document.getElementById('journalVoucherStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (status) params.append('status', status);

        const response = await fetch(`${API_BASE}/api/financial/journal-vouchers?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentJournalVouchers = data.vouchers || [];
            displayJournalVouchers(currentJournalVouchers);
        }
    } catch (error) {
        console.error('Error loading journal vouchers:', error);
        showError('Load Error', 'Failed to load journal vouchers');
    }
}

function displayJournalVouchers(vouchers) {
    const tbody = document.getElementById('journalVouchersTableBody');
    tbody.innerHTML = '';

    vouchers.forEach(v => {
        const row = document.createElement('tr');
        const date = new Date(v.voucher_date).toLocaleDateString();
        row.innerHTML = `
            <td>${v.voucher_number}</td>
            <td>${date}</td>
            <td>${v.description || '-'}</td>
            <td>${v.reference_number || '-'}</td>
            <td>₨ ${parseFloat(v.total_amount).toFixed(2)}</td>
            <td><span class="status-${v.status}">${v.status}</span></td>
            <td>${v.prepared_by_name || '-'}</td>
            <td>
                <button class="btn-small btn-info" onclick="viewJournalVoucher(${v.id})">View</button>
                ${v.status === 'draft' ? `<button class="btn-small btn-primary" onclick="postJournalVoucher(${v.id})">Post</button>` : ''}
                ${v.status === 'draft' ? `<button class="btn-small btn-danger" onclick="cancelJournalVoucher(${v.id})">Cancel</button>` : ''}
            </td>
        `;
        tbody.appendChild(row);
    });

    if (vouchers.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No journal vouchers found</td></tr>';
    }
}

function createJournalVoucher() {
    const form = document.getElementById('journalVoucherForm');
    if (form) form.reset();
    document.getElementById('journalVoucherId').value = '';
    document.getElementById('jnvEntriesBody').innerHTML = '';
    document.getElementById('jnvDebitTotal').textContent = '0.00';
    document.getElementById('jnvCreditTotal').textContent = '0.00';
    document.getElementById('jnvDebitTotal').parentElement.style.color = 'inherit';
    document.getElementById('jnvDate').valueAsDate = new Date();
    
    // Add two initial rows
    addJnvEntryRow();
    addJnvEntryRow();

    formChangedState['journalVoucherModal'] = false;
    openModal('journalVoucherModal');
}

function addJnvEntryRow(data = null) {
    const tbody = document.getElementById('jnvEntriesBody');
    const row = document.createElement('tr');
    row.className = 'jnv-entry-row';
    
    row.innerHTML = `
        <td><input type="text" class="form-control jnv-account" placeholder="e.g. Sales, Cash" value="${data ? data.account_name : ''}" required></td>
        <td>
            <select class="form-control jnv-entity-type">
                <option value="platform" ${data?.entity_type === 'platform' ? 'selected' : ''}>Platform</option>
                <option value="rider" ${data?.entity_type === 'rider' ? 'selected' : ''}>Rider</option>
                <option value="store" ${data?.entity_type === 'store' ? 'selected' : ''}>Store</option>
                <option value="customer" ${data?.entity_type === 'customer' ? 'selected' : ''}>Customer</option>
                <option value="vendor" ${data?.entity_type === 'vendor' ? 'selected' : ''}>Vendor</option>
                <option value="other" ${data?.entity_type === 'other' ? 'selected' : ''}>Other</option>
            </select>
        </td>
        <td><input type="number" class="form-control jnv-entity-id" placeholder="ID" value="${data ? data.entity_id : ''}"></td>
        <td>
            <select class="form-control jnv-entry-type">
                <option value="debit" ${data?.entry_type === 'debit' ? 'selected' : ''}>Debit</option>
                <option value="credit" ${data?.entry_type === 'credit' ? 'selected' : ''}>Credit</option>
            </select>
        </td>
        <td><input type="number" class="form-control jnv-amount" step="0.01" min="0" placeholder="0.00" value="${data ? data.amount : ''}" required></td>
        <td><input type="text" class="form-control jnv-row-desc" placeholder="Detail" value="${data ? data.description || '' : ''}"></td>
        <td><button type="button" class="btn-small btn-danger" onclick="this.closest('tr').remove(); calculateJnvTotals();"><i class="fas fa-trash"></i></button></td>
    `;
    
    tbody.appendChild(row);
    
    // Add listeners for total calculation
    row.querySelector('.jnv-amount').addEventListener('input', calculateJnvTotals);
    row.querySelector('.jnv-entry-type').addEventListener('change', calculateJnvTotals);
}

function calculateJnvTotals() {
    let debitTotal = 0;
    let creditTotal = 0;
    
    document.querySelectorAll('.jnv-entry-row').forEach(row => {
        const amount = parseFloat(row.querySelector('.jnv-amount').value) || 0;
        const type = row.querySelector('.jnv-entry-type').value;
        
        if (type === 'debit') debitTotal += amount;
        else creditTotal += amount;
    });
    
    document.getElementById('jnvDebitTotal').textContent = debitTotal.toFixed(2);
    document.getElementById('jnvCreditTotal').textContent = creditTotal.toFixed(2);
    
    // Highlight if imbalanced
    const totalCell = document.getElementById('jnvDebitTotal').parentElement;
    if (debitTotal !== creditTotal) {
        totalCell.style.color = 'red';
    } else {
        totalCell.style.color = 'inherit';
    }
    
    return { debitTotal, creditTotal };
}

async function submitJournalVoucher() {
    const { debitTotal, creditTotal } = calculateJnvTotals();
    
    if (debitTotal !== creditTotal) {
        showError('Imbalanced Voucher', 'Total Debits must equal Total Credits');
        return;
    }
    
    if (debitTotal <= 0) {
        showError('Invalid Amount', 'Voucher amount must be greater than zero');
        return;
    }

    const entries = [];
    document.querySelectorAll('.jnv-entry-row').forEach(row => {
        entries.push({
            account_name: row.querySelector('.jnv-account').value,
            entity_type: row.querySelector('.jnv-entity-type').value,
            entity_id: row.querySelector('.jnv-entity-id').value || null,
            entry_type: row.querySelector('.jnv-entry-type').value,
            amount: parseFloat(row.querySelector('.jnv-amount').value),
            description: row.querySelector('.jnv-row-desc').value
        });
    });

    const payload = {
        voucher_date: document.getElementById('jnvDate').value,
        reference_number: document.getElementById('jnvReference').value,
        description: document.getElementById('jnvDescription').value,
        total_amount: debitTotal,
        entries
    };

    try {
        const response = await fetch(`${API_BASE}/api/financial/journal-vouchers`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Journal Voucher created as draft');
            closeModal('journalVoucherModal');
            loadJournalVouchers();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error submitting JNV:', error);
        showError('Error', 'Failed to save journal voucher');
    }
}

async function postJournalVoucher(id) {
    if (!confirm('Are you sure you want to post this voucher to the master ledger? This action cannot be undone.')) return;

    try {
        const response = await fetch(`${API_BASE}/api/financial/journal-vouchers/${id}/post`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Voucher posted successfully');
            loadJournalVouchers();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        showError('Error', 'Failed to post voucher');
    }
}

async function cancelJournalVoucher(id) {
    if (!confirm('Are you sure you want to cancel this draft voucher?')) return;

    try {
        const response = await fetch(`${API_BASE}/api/financial/journal-vouchers/${id}/cancel`, {
            method: 'PUT',
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Voucher cancelled');
            loadJournalVouchers();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        showError('Error', 'Failed to cancel voucher');
    }
}

async function viewJournalVoucher(id) {
    try {
        const response = await fetch(`${API_BASE}/api/financial/journal-vouchers/${id}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        
        if (data.success) {
            const v = data.voucher;
            const entries = data.entries;
            
            let entryRows = entries.map(e => `
                <tr>
                    <td>${e.account_name}</td>
                    <td>${e.entity_type}</td>
                    <td>${e.entity_id || '-'}</td>
                    <td><span class="badge badge-${e.entry_type}">${e.entry_type.toUpperCase()}</span></td>
                    <td>₨ ${parseFloat(e.amount).toFixed(2)}</td>
                    <td>${e.description || '-'}</td>
                </tr>
            `).join('');
            
            const details = `
                <div style="margin-bottom: 1rem;">
                    <strong>Voucher #:</strong> ${v.voucher_number}<br>
                    <strong>Date:</strong> ${new Date(v.voucher_date).toLocaleDateString()}<br>
                    <strong>Status:</strong> <span class="status-${v.status}">${v.status}</span><br>
                    <strong>Description:</strong> ${v.description || '-'}<br>
                    <strong>Ref #:</strong> ${v.reference_number || '-'}<br>
                    <strong>Prepared By:</strong> ${v.prepared_by_name || '-'}<br>
                </div>
                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>Account</th>
                                <th>Entity</th>
                                <th>ID</th>
                                <th>Type</th>
                                <th>Amount</th>
                                <th>Desc</th>
                            </tr>
                        </thead>
                        <tbody>${entryRows}</tbody>
                    </table>
                </div>
            `;
            
            showInfo('Journal Voucher Details', details, 20000);
        }
    } catch (error) {
        showError('Error', 'Failed to load voucher details');
    }
}

function initializeFinancialForms() {
    // Initialize dynamic voucher type handlers
    if (window.handleVoucherTypeChange) {
        handleVoucherTypeChange('payeeType', 'payeeName', 'payeeSelect', 'payeeId', 'addExpenseTypeBtn');
        handleVoucherTypeChange('payerType', 'payerName', 'payerSelect', 'payerId', 'addPayerExpenseTypeBtn');
    }

    document.getElementById('paymentVoucherForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (typeof validateForm === 'function' && !validateForm('paymentVoucherForm')) return;
        await submitPaymentVoucher();
    });
    trackFormChanges('paymentVoucherForm', 'paymentVoucherModal');
    
    document.getElementById('receiptVoucherForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (typeof validateForm === 'function' && !validateForm('receiptVoucherForm')) return;
        await submitReceiptVoucher();
    });
    trackFormChanges('receiptVoucherForm', 'receiptVoucherModal');
    
    document.getElementById('transactionForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (typeof validateForm === 'function' && !validateForm('transactionForm')) return;
        await submitTransaction();
    });
    trackFormChanges('transactionForm', 'transactionModal');
    
    document.getElementById('riderCashForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (typeof validateForm === 'function' && !validateForm('riderCashForm')) return;
        await submitRiderCash();
    });
    trackFormChanges('riderCashForm', 'riderCashModal');
    
    document.getElementById('storeSettlementForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (typeof validateForm === 'function' && !validateForm('storeSettlementForm')) return;
        await submitStoreSettlement();
    });
    trackFormChanges('storeSettlementForm', 'storeSettlementModal');
    
    document.getElementById('expenseForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (typeof validateForm === 'function' && !validateForm('expenseForm')) return;
        await submitExpense();
    });
    trackFormChanges('expenseForm', 'expenseModal');
    
    document.getElementById('journalVoucherForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (typeof validateForm === 'function' && !validateForm('journalVoucherForm')) return;
        await submitJournalVoucher();
    });
    trackFormChanges('journalVoucherForm', 'journalVoucherModal');
    
    document.getElementById('addJnvEntryRowBtn')?.addEventListener('click', () => {
        addJnvEntryRow();
    });

    document.getElementById('generateReportForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        await submitGenerateReport();
    });

    // Report Type Change Handler
    const reportTypeSelect = document.getElementById('reportTypeModal');
    if (reportTypeSelect) {
        reportTypeSelect.addEventListener('change', function() {
            const riderGroup = document.getElementById('reportRiderSelectGroup');
            const riderSelect = document.getElementById('reportRiderSelect');
            
            if (
                this.value === 'rider_fuel_report' ||
                this.value === 'rider_cash_report' ||
                this.value === 'rider_orders_report' ||
                this.value === 'rider_payments_report' ||
                this.value === 'rider_receivings_report' ||
                this.value === 'rider_petrol_report' ||
                this.value === 'rider_daily_mileage_report' ||
                this.value === 'rider_daily_activity_report' ||
                this.value === 'rider_day_closing_report'
            ) {
                if (riderGroup) riderGroup.style.display = 'block';
                // Populate riders if needed
                if (riderSelect && riderSelect.options.length <= 1 && window.AppState && window.AppState.riders) {
                     window.AppState.riders.forEach(r => {
                        const opt = document.createElement('option');
                        opt.value = r.id;
                        opt.textContent = `${r.first_name} ${r.last_name || ''}`.trim();
                        riderSelect.appendChild(opt);
                     });
                }
            } else {
                if (riderGroup) riderGroup.style.display = 'none';
                if (riderSelect) riderSelect.value = '';
            }
        });
    }

    document.getElementById('addBankForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        await submitAddBank();
    });
}

async function submitAddBank() {
    const form = document.getElementById('addBankForm');
    const formData = new FormData(form);
    const payload = Object.fromEntries(formData.entries());

    try {
        const response = await fetch(`${API_BASE}/api/financial/banks`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Bank added successfully');
            closeModal('addBankModal');
            form.reset();
            
            // Refresh lists if currently selected type is bank
            const payeeType = document.getElementById('payeeType');
            if (payeeType && payeeType.value === 'bank') {
                 payeeType.dispatchEvent(new Event('change'));
            }
            const payerType = document.getElementById('payerType');
            if (payerType && payerType.value === 'bank') {
                 payerType.dispatchEvent(new Event('change'));
            }
        } else {
            showError('Error', data.message || 'Failed to add bank');
        }
    } catch (error) {
        console.error('Error adding bank:', error);
        showError('Error', 'Failed to add bank');
    }
}

async function loadFinancialDashboard() {
    try {
        const period = document.getElementById('financialPeriodFilter')?.value || 'month';
        const response = await fetch(`${API_BASE}/api/financial/dashboard?period=${period}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            document.getElementById('totalIncomeAmount').textContent = `₨ ${parseFloat(data.stats.income).toFixed(2)}`;
            document.getElementById('totalExpenseAmount').textContent = `₨ ${parseFloat(data.stats.expense).toFixed(2)}`;
            document.getElementById('totalSettlementsAmount').textContent = `₨ ${parseFloat(data.stats.settlement).toFixed(2)}`;
            const netProfit = data.stats.income - (data.stats.expense + data.stats.settlement + (data.stats.refund || 0));
            document.getElementById('netProfitAmount').textContent = `₨ ${parseFloat(netProfit).toFixed(2)}`;
            document.getElementById('paymentVouchersAmount').textContent = `₨ ${parseFloat(data.stats.paymentVouchers).toFixed(2)}`;
            document.getElementById('receiptVouchersAmount').textContent = `₨ ${parseFloat(data.stats.receiptVouchers).toFixed(2)}`;
            document.getElementById('totalRiderCashAmount').textContent = `₨ ${parseFloat(data.stats.riderCashSubmitted).toFixed(2)}`;
            if (document.getElementById('cashInHandAmount')) {
                document.getElementById('cashInHandAmount').textContent = `₨ ${parseFloat(data.stats.cashInHand).toFixed(2)}`;
            }
        }
    } catch (error) {
        console.error('Error loading financial dashboard:', error);
        showError('Dashboard Error', 'Failed to load financial dashboard');
    }
}

function showCashLedger() {
    loadCashLedger();
    openModal('cashLedgerModal');
}

async function loadCashLedger() {
    try {
        const period = document.getElementById('ledgerPeriod')?.value || 'month';
        const response = await fetch(`${API_BASE}/api/financial/cash-ledger?period=${period}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            const tbody = document.getElementById('cashLedgerBody');
            tbody.innerHTML = '';
            let total = 0;

            data.transactions.forEach(t => {
                const row = document.createElement('tr');
                const date = new Date(t.created_at).toLocaleString();
                const amount = parseFloat(t.amount);
                
                // Determine if amount should be displayed as positive or negative based on type
                let displayAmount = amount;
                let amountClass = 'text-success'; // Green for incoming
                
                if (['expense', 'settlement', 'refund'].includes(t.transaction_type)) {
                    displayAmount = -amount;
                    amountClass = 'text-danger'; // Red for outgoing
                }
                
                total += displayAmount;

                row.innerHTML = `
                    <td>${date}</td>
                    <td>${t.description || '-'}</td>
                    <td><span class="badge badge-${t.transaction_type}">${t.transaction_type}</span></td>
                    <td>${t.category || '-'}</td>
                    <td class="${amountClass}" style="font-weight:bold">₨ ${displayAmount.toFixed(2)}</td>
                    <td>${t.created_by_name || '-'}</td>
                `;
                tbody.appendChild(row);
            });

            if (data.transactions.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" style="text-align: center; padding: 2rem;">No cash transactions found for this period</td></tr>';
            }
            
            document.getElementById('ledgerTotal').textContent = `₨ ${total.toFixed(2)}`;
        }
    } catch (error) {
        console.error('Error loading cash ledger:', error);
        showError('Load Error', 'Failed to load cash ledger');
    }
}

async function loadTransactions() {
    try {
        const type = document.getElementById('transactionTypeFilter')?.value || '';
        const status = document.getElementById('transactionStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (type) params.append('type', type);
        if (status) params.append('status', status);

        const response = await fetch(`${API_BASE}/api/financial/transactions?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentTransactions = data.transactions || [];
            displayTransactions(currentTransactions);
        }
    } catch (error) {
        console.error('Error loading transactions:', error);
        showError('Load Error', 'Failed to load transactions');
    }
}

function displayTransactions(transactions) {
    const tbody = document.getElementById('transactionsTableBody');
    tbody.innerHTML = '';

    transactions.forEach(t => {
        const row = document.createElement('tr');
        const date = new Date(t.created_at).toLocaleDateString();
        row.innerHTML = `
            <td>${t.id}</td>
            <td>${t.transaction_number}</td>
            <td><span class="badge badge-${t.transaction_type}">${t.transaction_type}</span></td>
            <td>${t.description || '-'}</td>
            <td>₨ ${parseFloat(t.amount).toFixed(2)}</td>
            <td>${t.payment_method}</td>
            <td><span class="status-${t.status}">${t.status}</span></td>
            <td>${date}</td>
            <td>
                <button class="btn-small btn-info" onclick="viewTransaction(${t.id})">View</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (transactions.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 2rem;">No transactions found</td></tr>';
    }
}

async function loadPaymentVouchers() {
    try {
        const status = document.getElementById('paymentVoucherStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (status) params.append('status', status);
        params.append('payment_method', 'cash');

        const response = await fetch(`${API_BASE}/api/financial/payment-vouchers?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentPaymentVouchers = data.vouchers || [];
            displayPaymentVouchers(currentPaymentVouchers);
        }
    } catch (error) {
        console.error('Error loading payment vouchers:', error);
        showError('Load Error', 'Failed to load payment vouchers');
    }
}

async function loadBankPaymentVouchers() {
    try {
        const status = document.getElementById('bankPaymentVoucherStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (status) params.append('status', status);
        params.append('payment_method', 'bank');

        const response = await fetch(`${API_BASE}/api/financial/payment-vouchers?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            displayBankPaymentVouchers(data.vouchers || []);
        }
    } catch (error) {
        console.error('Error loading bank payment vouchers:', error);
        showError('Load Error', 'Failed to load bank payment vouchers');
    }
}

function displayBankPaymentVouchers(vouchers) {
    const tbody = document.getElementById('bankPaymentVouchersTableBody');
    if (!tbody) return;
    tbody.innerHTML = '';

    vouchers.forEach(v => {
        const row = document.createElement('tr');
        const date = new Date(v.voucher_date).toLocaleDateString();
        row.innerHTML = `
            <td>${v.voucher_number}</td>
            <td>${date}</td>
            <td>${v.payee_name}</td>
            <td>${v.payee_type}</td>
            <td>₨ ${parseFloat(v.amount).toFixed(2)}</td>
            <td>${v.purpose || '-'}</td>
            <td><span class="status-${v.status}">${v.status}</span></td>
            <td>
                <button class="btn-small btn-info" onclick="editPaymentVoucher(${v.id})">Edit</button>
                <button class="btn-small btn-primary" onclick="approvePaymentVoucher(${v.id})">Approve</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (vouchers.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No bank payment vouchers found</td></tr>';
    }
}

function displayPaymentVouchers(vouchers) {
    const tbody = document.getElementById('paymentVouchersTableBody');
    tbody.innerHTML = '';

    vouchers.forEach(v => {
        const row = document.createElement('tr');
        const date = new Date(v.voucher_date).toLocaleDateString();
        row.innerHTML = `
            <td>${v.voucher_number}</td>
            <td>${date}</td>
            <td>${v.payee_name}</td>
            <td>${v.payee_type}</td>
            <td>₨ ${parseFloat(v.amount).toFixed(2)}</td>
            <td>${v.purpose || '-'}</td>
            <td><span class="status-${v.status}">${v.status}</span></td>
            <td>
                <button class="btn-small btn-info" onclick="editPaymentVoucher(${v.id})">Edit</button>
                <button class="btn-small btn-primary" onclick="approvePaymentVoucher(${v.id})">Approve</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (vouchers.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No payment vouchers found</td></tr>';
    }
}

async function loadReceiptVouchers() {
    try {
        const status = document.getElementById('receiptVoucherStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (status) params.append('status', status);
        params.append('payment_method', 'cash');

        const response = await fetch(`${API_BASE}/api/financial/receipt-vouchers?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentReceiptVouchers = data.vouchers || [];
            displayReceiptVouchers(currentReceiptVouchers);
        }
    } catch (error) {
        console.error('Error loading receipt vouchers:', error);
        showError('Load Error', 'Failed to load receipt vouchers');
    }
}

async function loadBankReceiptVouchers() {
    try {
        const status = document.getElementById('bankReceiptVoucherStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (status) params.append('status', status);
        params.append('payment_method', 'bank');

        const response = await fetch(`${API_BASE}/api/financial/receipt-vouchers?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            displayBankReceiptVouchers(data.vouchers || []);
        }
    } catch (error) {
        console.error('Error loading bank receipt vouchers:', error);
        showError('Load Error', 'Failed to load bank receipt vouchers');
    }
}

function displayBankReceiptVouchers(vouchers) {
    const tbody = document.getElementById('bankReceiptVouchersTableBody');
    if (!tbody) return;
    tbody.innerHTML = '';

    vouchers.forEach(v => {
        const row = document.createElement('tr');
        const date = new Date(v.voucher_date).toLocaleDateString();
        row.innerHTML = `
            <td>${v.voucher_number}</td>
            <td>${date}</td>
            <td>${v.payer_name}</td>
            <td>${v.payer_type}</td>
            <td>₨ ${parseFloat(v.amount).toFixed(2)}</td>
            <td>${v.description || '-'}</td>
            <td><span class="status-${v.status}">${v.status}</span></td>
            <td>
                <button class="btn-small btn-info" onclick="editReceiptVoucher(${v.id})">Edit</button>
                <button class="btn-small btn-primary" onclick="approveReceiptVoucher(${v.id})">Approve</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (vouchers.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No bank receipt vouchers found</td></tr>';
    }
}

function displayReceiptVouchers(vouchers) {
    const tbody = document.getElementById('receiptVouchersTableBody');
    tbody.innerHTML = '';

    vouchers.forEach(v => {
        const row = document.createElement('tr');
        const date = new Date(v.voucher_date).toLocaleDateString();
        row.innerHTML = `
            <td>${v.voucher_number}</td>
            <td>${date}</td>
            <td>${v.payer_name}</td>
            <td>${v.payer_type}</td>
            <td>₨ ${parseFloat(v.amount).toFixed(2)}</td>
            <td>${v.description || '-'}</td>
            <td><span class="status-${v.status}">${v.status}</span></td>
            <td>
                <button class="btn-small btn-info" onclick="editReceiptVoucher(${v.id})">Edit</button>
                <button class="btn-small btn-primary" onclick="approveReceiptVoucher(${v.id})">Approve</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (vouchers.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No receipt vouchers found</td></tr>';
    }
}

async function loadRiderCash() {
    try {
        const type = document.getElementById('riderCashMovementTypeFilter')?.value || '';
        const status = document.getElementById('riderCashStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (type) params.append('type', type);
        if (status) params.append('status', status);

        const response = await fetch(`${API_BASE}/api/financial/rider-cash?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentRiderCash = data.movements || [];
            displayRiderCash(currentRiderCash);
        }
    } catch (error) {
        console.error('Error loading rider cash movements:', error);
        showError('Load Error', 'Failed to load rider cash movements');
    }
}

function displayRiderCash(movements) {
    const tbody = document.getElementById('riderCashTableBody');
    tbody.innerHTML = '';

    movements.forEach(m => {
        const row = document.createElement('tr');
        const date = new Date(m.movement_date).toLocaleDateString();
        const riderName = `${m.first_name || ''} ${m.last_name || ''}`.trim();
        row.innerHTML = `
            <td>${m.movement_number}</td>
            <td>${riderName}</td>
            <td>${date}</td>
            <td>${m.movement_type.replace(/_/g, ' ')}</td>
            <td>₨ ${parseFloat(m.amount).toFixed(2)}</td>
            <td><span class="status-${m.status}">${m.status}</span></td>
            <td>${m.recorded_by_name || '-'}</td>
            <td>
                <button class="btn-small btn-info" onclick="editRiderCash(${m.id})">Edit</button>
                <button class="btn-small btn-primary" onclick="approveRiderCash(${m.id})">Approve</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (movements.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No rider cash movements found</td></tr>';
    }
}

async function loadStoreSettlements() {
    try {
        const status = document.getElementById('storeSettlementStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (status) params.append('status', status);

        const response = await fetch(`${API_BASE}/api/financial/store-settlements?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentStoreSettlements = data.settlements || [];
            displayStoreSettlements(currentStoreSettlements);
        }
    } catch (error) {
        console.error('Error loading store settlements:', error);
        showError('Load Error', 'Failed to load store settlements');
    }
}

function displayStoreSettlements(settlements) {
    const tbody = document.getElementById('storeSettlementsTableBody');
    tbody.innerHTML = '';

    settlements.forEach(s => {
        const row = document.createElement('tr');
        const date = new Date(s.settlement_date).toLocaleDateString();
        const from = s.period_from ? new Date(s.period_from).toLocaleDateString() : '-';
        const to = s.period_to ? new Date(s.period_to).toLocaleDateString() : '-';
        row.innerHTML = `
            <td>${s.settlement_number}</td>
            <td>${s.store_name}</td>
            <td>${date}</td>
            <td>${from}</td>
            <td>${to}</td>
            <td>₨ ${parseFloat(s.net_amount).toFixed(2)}</td>
            <td><span class="status-${s.status}">${s.status}</span></td>
            <td>
                <button class="btn-small btn-info" onclick="editStoreSettlement(${s.id})">Edit</button>
                <button class="btn-small btn-primary" onclick="approveStoreSettlement(${s.id})">Approve</button>
                ${s.status === 'approved' ? `<button class="btn-small btn-success" onclick="payStoreSettlement(${s.id})" style="background-color: #28a745; color: white; margin-left: 4px;">Pay</button>` : ''}
            </td>
        `;
        tbody.appendChild(row);
    });

    if (settlements.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No store settlements found</td></tr>';
    }
}

async function loadExpenses() {
    try {
        const category = document.getElementById('expenseCategoryFilter')?.value || '';
        const status = document.getElementById('expenseStatusFilter')?.value || '';
        const params = new URLSearchParams();
        if (category) params.append('category', category);
        if (status) params.append('status', status);

        const response = await fetch(`${API_BASE}/api/financial/expenses?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentExpenses = data.expenses || [];
            displayExpenses(currentExpenses);
        }
    } catch (error) {
        console.error('Error loading expenses:', error);
        showError('Load Error', 'Failed to load expenses');
    }
}

function displayExpenses(expenses) {
    const tbody = document.getElementById('expensesTableBody');
    tbody.innerHTML = '';

    expenses.forEach(e => {
        const row = document.createElement('tr');
        const date = new Date(e.expense_date).toLocaleDateString();
        let actionButtons = `<button class="btn-small btn-info" onclick="editExpense(${e.id})">Edit</button>`;
        
        if (e.status === 'pending') {
            actionButtons += ` <button class="btn-small btn-primary" onclick="approveExpense(${e.id})">Approve</button>`;
        } else if (e.status === 'approved') {
            actionButtons += ` <button class="btn-small btn-success" onclick="payExpense(${e.id})">Pay</button>`;
        }

        row.innerHTML = `
            <td>${e.expense_number}</td>
            <td>${date}</td>
            <td>${e.category}</td>
            <td>${e.description || '-'}</td>
            <td>₨ ${parseFloat(e.amount).toFixed(2)}</td>
            <td>${e.vendor_name || '-'}</td>
            <td><span class="status-${e.status}">${e.status}</span></td>
            <td>${actionButtons}</td>
        `;
        tbody.appendChild(row);
    });

    if (expenses.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No expenses found</td></tr>';
    }
}

// === Store Settlement Logic ===

function setupStoreSettlementListeners() {
    const storeSelect = document.getElementById('settlementStoreSelect');
    const autoCalcCheckbox = document.getElementById('autoCalculateSettlement');
    
    if (storeSelect) {
        storeSelect.addEventListener('change', () => {
            if (autoCalcCheckbox && autoCalcCheckbox.checked) {
                loadUnsettledItems(storeSelect.value);
            }
        });
    }

    if (autoCalcCheckbox) {
        autoCalcCheckbox.addEventListener('change', () => {
            const itemsContainer = document.getElementById('unsettledItemsContainer');
            const amountInput = document.getElementById('settlementAmount');
            
            if (autoCalcCheckbox.checked) {
                itemsContainer.style.display = 'block';
                amountInput.readOnly = true;
                if (storeSelect.value) {
                    loadUnsettledItems(storeSelect.value);
                }
            } else {
                itemsContainer.style.display = 'none';
                amountInput.readOnly = false;
                amountInput.value = '';
            }
        });
    }
}

async function loadUnsettledItems(storeId) {
    if (!storeId) return;
    
    try {
        const response = await fetch(`${API_BASE}/api/financial/store-settlements/unsettled-items?store_id=${storeId}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        
        if (data.success) {
            displayUnsettledItems(data.items, data.summary);
            // Auto fill the amount
            document.getElementById('settlementAmount').value = data.summary.net_amount.toFixed(2);
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error loading unsettled items:', error);
        showError('Error', 'Failed to load unpaid items');
    }
}

function displayUnsettledItems(items, summary) {
    const tbody = document.getElementById('unsettledItemsBody');
    tbody.innerHTML = '';
    
    items.forEach(item => {
        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${new Date(item.order_date).toLocaleDateString()}</td>
            <td>${item.order_number}</td>
            <td>${item.product_name} (${item.variant_label || '-'})</td>
            <td>${item.quantity}</td>
            <td>₨ ${(item.price * item.quantity).toFixed(2)}</td>
        `;
        tbody.appendChild(row);
    });
    
    if (items.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center;">No unpaid items found</td></tr>';
    }
    
    document.getElementById('unsettledTotalSales').textContent = `₨ ${summary.total_orders_amount.toFixed(2)}`;
    document.getElementById('unsettledCommissionRate').textContent = summary.commission_rate;
    document.getElementById('unsettledCommission').textContent = `₨ ${summary.commissions.toFixed(2)}`;
    document.getElementById('unsettledNetPayable').textContent = `₨ ${summary.net_amount.toFixed(2)}`;
}

async function loadFinancialReports() {
    try {
        const type = document.getElementById('reportTypeFilter')?.value || '';
        const params = new URLSearchParams();
        if (type) params.append('type', type);

        const response = await fetch(`${API_BASE}/api/financial/reports?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            currentReports = data.reports || [];
            displayReports(currentReports);
        }
    } catch (error) {
        console.error('Error loading reports:', error);
        showError('Load Error', 'Failed to load reports');
    }
}

function displayReports(reports) {
    const tbody = document.getElementById('reportsTableBody');
    tbody.innerHTML = '';

    reports.forEach(r => {
        const row = document.createElement('tr');
        const fromDate = r.period_from ? new Date(r.period_from).toLocaleDateString() : '-';
        const toDate = r.period_to ? new Date(r.period_to).toLocaleDateString() : '-';
        const created = new Date(r.created_at).toLocaleDateString();
        row.innerHTML = `
            <td>${r.report_number}</td>
            <td>${r.report_type.replace(/_/g, ' ')}</td>
            <td>${fromDate}</td>
            <td>${toDate}</td>
            <td>₨ ${parseFloat(r.total_income).toFixed(2)}</td>
            <td>₨ ${parseFloat(r.total_expense).toFixed(2)}</td>
            <td>₨ ${parseFloat(r.net_profit).toFixed(2)}</td>
            <td>${created}</td>
            <td>
                <button class="btn-small btn-info" onclick="viewReport(${r.id})">View</button>
                <button class="btn-small btn-secondary" onclick="generatePDF(${r.id})">Download</button>
                <button class="btn-small btn-danger" onclick="deleteReport(${r.id})" style="background-color: #dc3545; color: white; margin-left: 4px;">Delete</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (reports.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 2rem;">No reports found</td></tr>';
    }
}

async function deleteReport(id) {
    if (!confirm('Are you sure you want to delete this report? This action cannot be undone.')) {
        return;
    }

    try {
        const response = await fetch(`${API_BASE}/api/financial/reports/${id}`, {
            method: 'DELETE',
            headers: {
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            }
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Report deleted successfully');
            loadFinancialReports();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error deleting report:', error);
        showError('Error', 'Failed to delete report');
    }
}

async function payStoreSettlement(id) {
    if (!confirm('Are you sure you want to mark this settlement as PAID? This will record a financial transaction.')) return;

    try {
        const response = await fetch(`${API_BASE}/api/financial/store-settlements/${id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ status: 'paid' })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Settlement marked as paid');
            loadStoreSettlements();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error paying settlement:', error);
        showError('Error', 'Failed to pay settlement');
    }
}

function createPaymentVoucher() {
    const form = document.getElementById('paymentVoucherForm');
    if (form) form.reset();
    const idInput = document.getElementById('paymentVoucherId');
    if (idInput) idInput.value = '';
    
    // Set default payment method to cash for CPV
    const methodSelect = document.getElementById('paymentMethodPV');
    if (methodSelect) methodSelect.value = 'cash';

    document.querySelector('#paymentVoucherModal h2').textContent = 'Create Cash Payment Voucher (CPV)';
    document.querySelector('#paymentVoucherModal .btn-primary').textContent = 'Create Voucher';
    
    formChangedState['paymentVoucherModal'] = false;
    openModal('paymentVoucherModal');
}

function createBankPaymentVoucher() {
    const form = document.getElementById('paymentVoucherForm');
    if (form) form.reset();
    const idInput = document.getElementById('paymentVoucherId');
    if (idInput) idInput.value = '';
    
    // Set default payment method to bank_transfer for BPV
    const methodSelect = document.getElementById('paymentMethodPV');
    if (methodSelect) methodSelect.value = 'bank_transfer';

    document.querySelector('#paymentVoucherModal h2').textContent = 'Create Bank Payment Voucher (BPV)';
    document.querySelector('#paymentVoucherModal .btn-primary').textContent = 'Create Voucher';
    
    formChangedState['paymentVoucherModal'] = false;
    openModal('paymentVoucherModal');
}

async function submitPaymentVoucher() {
    const id = document.getElementById('paymentVoucherId').value;
    const payeeName = document.getElementById('payeeName').value;
    const payeeType = document.getElementById('payeeType').value;
    const payeeId = document.getElementById('payeeId').value;
    const amount = parseFloat(document.getElementById('paymentAmount').value);
    const purpose = document.getElementById('paymentPurpose').value;
    const paymentMethod = document.getElementById('paymentMethodPV').value;
    const chequeNumber = document.getElementById('paymentChequeNoPV').value;

    const payload = {
        payee_name: payeeName,
        payee_type: payeeType,
        payee_id: (payeeType === 'expense') ? null : (payeeId || null),
        amount,
        purpose,
        description: '',
        payment_method: paymentMethod,
        check_number: (paymentMethod === 'cheque') ? chequeNumber : null,
        bank_details: null
    };

    try {
        const url = id ? `${API_BASE}/api/financial/payment-vouchers/${id}` : `${API_BASE}/api/financial/payment-vouchers`;
        const method = id ? 'PUT' : 'POST';

        const response = await fetch(url, {
            method,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', id ? 'Payment voucher updated' : 'Payment voucher created successfully');
            closeModal('paymentVoucherModal');
            loadPaymentVouchers();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error submitting payment voucher:', error);
        showError('Error', 'Failed to save payment voucher');
    }
}

async function editPaymentVoucher(id) {
    const voucher = currentPaymentVouchers.find(v => v.id === id);
    if (!voucher) return;

    document.getElementById('paymentVoucherId').value = voucher.id;
    document.getElementById('paymentAmount').value = voucher.amount;
    document.getElementById('paymentPurpose').value = voucher.purpose || '';
    document.getElementById('paymentMethodPV').value = voucher.payment_method;
    
    // Populate cheque number if applicable
    const chequeInput = document.getElementById('paymentChequeNoPV');
    if (chequeInput) {
        // Fallback to check_number if cheque_number is missing (database inconsistency)
        chequeInput.value = voucher.cheque_number || voucher.check_number || '';
    }
    // Trigger visibility toggle
    if (typeof toggleChequeInput === 'function') {
        toggleChequeInput('paymentMethodPV', 'paymentChequeContainerPV');
    }
    
    const payeeType = document.getElementById('payeeType');
    payeeType.value = voucher.payee_type;
    
    // UI elements
    const nameInput = document.getElementById('payeeName');
    const select = document.getElementById('payeeSelect');
    const hidden = document.getElementById('payeeId');
    const addBtn = document.getElementById('addExpenseTypeBtn');
    
    await updateVoucherTypeUI(voucher.payee_type, nameInput, select, hidden, addBtn);
    
    if (['store', 'rider', 'employee', 'expense'].includes(voucher.payee_type)) {
        if (voucher.payee_type === 'expense') {
             select.value = voucher.payee_name;
             hidden.value = ''; 
        } else {
             select.value = voucher.payee_id;
             hidden.value = voucher.payee_id;
        }
        nameInput.value = voucher.payee_name;
    } else {
        nameInput.value = voucher.payee_name;
    }

    document.querySelector('#paymentVoucherModal h2').textContent = 'Edit Payment Voucher';
    document.querySelector('#paymentVoucherModal .btn-primary').textContent = 'Update Voucher';

    formChangedState['paymentVoucherModal'] = false;
    openModal('paymentVoucherModal');
}

function createReceiptVoucher() {
    const form = document.getElementById('receiptVoucherForm');
    if (form) form.reset();
    const idInput = document.getElementById('receiptVoucherId');
    if (idInput) idInput.value = '';
    
    // Set default payment method to cash for CRV
    const methodSelect = document.getElementById('paymentMethodRV');
    if (methodSelect) methodSelect.value = 'cash';

    document.querySelector('#receiptVoucherModal h2').textContent = 'Create Cash Receipt Voucher (CRV)';
    document.querySelector('#receiptVoucherModal .btn-primary').textContent = 'Create Voucher';
    
    formChangedState['receiptVoucherModal'] = false;
    openModal('receiptVoucherModal');
}

function createBankReceiptVoucher() {
    const form = document.getElementById('receiptVoucherForm');
    if (form) form.reset();
    const idInput = document.getElementById('receiptVoucherId');
    if (idInput) idInput.value = '';
    
    // Set default payment method to bank_transfer for BRV
    const methodSelect = document.getElementById('paymentMethodRV');
    if (methodSelect) methodSelect.value = 'bank_transfer';

    document.querySelector('#receiptVoucherModal h2').textContent = 'Create Bank Receive Voucher (BRV)';
    document.querySelector('#receiptVoucherModal .btn-primary').textContent = 'Create Voucher';
    
    formChangedState['receiptVoucherModal'] = false;
    openModal('receiptVoucherModal');
}

async function submitReceiptVoucher() {
    const id = document.getElementById('receiptVoucherId').value;
    const payerName = document.getElementById('payerName').value;
    const payerType = document.getElementById('payerType').value;
    const payerId = document.getElementById('payerId').value;
    const amount = parseFloat(document.getElementById('receiptAmount').value);
    const description = document.getElementById('receiptDescription').value;
    const paymentMethod = document.getElementById('paymentMethodRV').value;

    const payload = {
        payer_name: payerName,
        payer_type: payerType,
        payer_id: (payerType === 'expense') ? null : (payerId || null),
        amount,
        description,
        details: '',
        payment_method: paymentMethod,
    cheque_number: null,
    bank_details: null
    };

    try {
        const url = id ? `${API_BASE}/api/financial/receipt-vouchers/${id}` : `${API_BASE}/api/financial/receipt-vouchers`;
        const method = id ? 'PUT' : 'POST';

        const response = await fetch(url, {
            method,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', id ? 'Receipt voucher updated' : 'Receipt voucher created successfully');
            closeModal('receiptVoucherModal');
            loadReceiptVouchers();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error submitting receipt voucher:', error);
        showError('Error', 'Failed to save receipt voucher');
    }
}

async function editReceiptVoucher(id) {
    const voucher = currentReceiptVouchers.find(v => v.id === id);
    if (!voucher) return;

    document.getElementById('receiptVoucherId').value = voucher.id;
    document.getElementById('receiptAmount').value = voucher.amount;
    document.getElementById('receiptDescription').value = voucher.description || '';
    document.getElementById('paymentMethodRV').value = voucher.payment_method;
    
    const payerType = document.getElementById('payerType');
    payerType.value = voucher.payer_type;
    
    // UI elements
    const nameInput = document.getElementById('payerName');
    const select = document.getElementById('payerSelect');
    const hidden = document.getElementById('payerId');
    const addBtn = document.getElementById('addPayerExpenseTypeBtn');
    
    await updateVoucherTypeUI(voucher.payer_type, nameInput, select, hidden, addBtn);
    
    if (['store', 'rider', 'employee', 'expense'].includes(voucher.payer_type)) {
        if (voucher.payer_type === 'expense') {
             select.value = voucher.payer_name;
             hidden.value = ''; 
        } else {
             select.value = voucher.payer_id;
             hidden.value = voucher.payer_id;
        }
        nameInput.value = voucher.payer_name;
    } else {
        nameInput.value = voucher.payer_name;
    }

    document.querySelector('#receiptVoucherModal h2').textContent = 'Edit Receipt Voucher';
    document.querySelector('#receiptVoucherModal .btn-primary').textContent = 'Update Voucher';

    formChangedState['receiptVoucherModal'] = false;
    openModal('receiptVoucherModal');
}

function createTransaction() {
    const form = document.getElementById('transactionForm');
    if (form) form.reset();
    const idInput = document.getElementById('transactionId');
    if (idInput) idInput.value = '';

    document.querySelector('#transactionModal h2').textContent = 'Record Transaction';
    document.querySelector('#transactionModal .btn-primary').textContent = 'Record Transaction';

    formChangedState['transactionModal'] = false;
    openModal('transactionModal');
}

async function submitTransaction() {
    const id = document.getElementById('transactionId').value;
    const amount = parseFloat(document.getElementById('transactionAmount').value);
    const type = document.getElementById('transactionType').value;
    const description = document.getElementById('transactionDescription').value;
    const paymentMethod = document.getElementById('transactionPaymentMethod').value;

    const payload = {
        transaction_type: type,
        amount,
        description,
        payment_method: paymentMethod,
        category: null
    };

    try {
        const url = id ? `${API_BASE}/api/financial/transactions/${id}` : `${API_BASE}/api/financial/transactions`;
        const method = id ? 'PUT' : 'POST';

        const response = await fetch(url, {
            method,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', id ? 'Transaction updated' : 'Transaction recorded successfully');
            closeModal('transactionModal');
            loadTransactions();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error submitting transaction:', error);
        showError('Error', 'Failed to save transaction');
    }
}

async function createRiderCash() {
    document.getElementById('riderCashForm').reset();
    document.getElementById('riderCashId').value = '';
    formChangedState['riderCashModal'] = false;
    document.querySelector('#riderCashModal h2').textContent = 'Record Rider Cash Movement';
    document.querySelector('#riderCashModal .btn-primary').textContent = 'Record Movement';
    await populateRidersDropdown();

    // Setup listeners for pending orders
    const riderSelect = document.getElementById('riderId');
    const typeSelect = document.getElementById('movementType');
    const container = document.getElementById('pendingOrdersContainer');
    
    // Reset container visibility
    if (container) container.style.display = 'none';

    // Global variables to track pending orders (ensure they are reset)
    window.pendingCashOrders = [];
    window.selectedPendingOrders = new Set();

    const checkPendingOrders = async () => {
        const riderId = riderSelect.value;
        const type = typeSelect.value;
        
        if (container && type === 'cash_submission' && riderId) {
            try {
                const response = await fetch(`${API_BASE}/api/financial/riders/${riderId}/pending-cash-orders`, {
                    headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
                });
                const data = await response.json();
                
                if (data.success && data.orders && data.orders.length > 0) {
                    window.pendingCashOrders = data.orders;
                    window.selectedPendingOrders = new Set(data.orders.map(o => o.id)); // Default select all
                    renderPendingOrdersTable();
                    container.style.display = 'block';
                } else {
                    window.pendingCashOrders = [];
                    window.selectedPendingOrders = new Set();
                    container.style.display = 'none';
                }
            } catch (e) {
                console.error('Error fetching pending orders:', e);
                container.style.display = 'none';
            }
        } else if (container) {
            container.style.display = 'none';
        }
    };
    
    // Remove existing listeners to avoid duplicates (though setting onchange property overwrites)
    riderSelect.onchange = checkPendingOrders;
    typeSelect.onchange = checkPendingOrders;
    
    openModal('riderCashModal');
}

function renderPendingOrdersTable() {
    const tbody = document.getElementById('pendingOrdersListBody');
    const totalEl = document.getElementById('pendingOrdersTotal');
    const selectAllCb = document.getElementById('selectAllPendingOrders');
    
    if (!tbody) return;

    tbody.innerHTML = '';
    let totalSelected = 0;

    window.pendingCashOrders.forEach(o => {
        const isSelected = window.selectedPendingOrders.has(o.id);
        if (isSelected) totalSelected += parseFloat(o.total_amount);

        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td style="text-align: center;"><input type="checkbox" class="pending-order-cb" value="${o.id}" ${isSelected ? 'checked' : ''} onchange="togglePendingOrder(${o.id}, this.checked)" style="cursor: pointer;"></td>
            <td>${o.order_number}</td>
            <td>${new Date(o.created_at).toLocaleDateString()}</td>
            <td style="text-align:right">₨ ${parseFloat(o.total_amount).toFixed(2)}</td>
        `;
        tbody.appendChild(tr);
    });

    if (totalEl) totalEl.textContent = `₨ ${totalSelected.toFixed(2)}`;
    
    const amountInput = document.getElementById('riderCashAmountInput');
    // Only auto-fill amount if it's 0 or matches previous total (to allow manual override)
    // But for simplicity in this flow, we update it if it's a cash submission
    if (amountInput && document.getElementById('movementType').value === 'cash_submission') {
         amountInput.value = totalSelected.toFixed(2);
    }
    
    if (selectAllCb) {
        selectAllCb.checked = window.pendingCashOrders.length > 0 && window.selectedPendingOrders.size === window.pendingCashOrders.length;
    }
}

function togglePendingOrder(id, checked) {
    if (checked) {
        window.selectedPendingOrders.add(id);
    } else {
        window.selectedPendingOrders.delete(id);
    }
    renderPendingOrdersTable();
}

function toggleAllPendingOrders(cb) {
    if (cb.checked) {
        window.selectedPendingOrders = new Set(window.pendingCashOrders.map(o => o.id));
    } else {
        window.selectedPendingOrders.clear();
    }
    renderPendingOrdersTable();
}

async function populateRidersDropdown() {
    try {
        const response = await fetch(`${API_BASE}/api/riders`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        
        const select = document.getElementById('riderId');
        if (select && data.riders) {
            const currentValue = select.value;
            select.innerHTML = '<option value="">-- Select Rider --</option>';
            data.riders.forEach(rider => {
                const option = document.createElement('option');
                option.value = rider.id;
                option.textContent = `${rider.first_name} ${rider.last_name} (${rider.phone})`;
                select.appendChild(option);
            });
            if (currentValue) select.value = currentValue;
        }
    } catch (error) {
        console.error('Error populating riders dropdown:', error);
    }
}

async function populateStoresDropdown() {
    try {
        const response = await fetch(`${API_BASE}/api/stores?admin=1`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        
        const select = document.getElementById('settlementStoreSelect');
        if (select && data.stores) {
            const currentValue = select.value;
            select.innerHTML = '<option value="">-- Select Store --</option>';
            data.stores.forEach(store => {
                const option = document.createElement('option');
                option.value = store.id;
                option.textContent = store.name;
                select.appendChild(option);
            });
            if (currentValue) select.value = currentValue;
        }
    } catch (error) {
        console.error('Error populating stores dropdown:', error);
    }
}

async function submitRiderCash() {
    const id = document.getElementById('riderCashId').value;
    const riderId = parseInt(document.getElementById('riderId').value);
    const movementType = document.getElementById('movementType').value;
    const amount = parseFloat(document.getElementById('riderCashAmountInput').value);
    const description = document.getElementById('riderCashDescription').value;

    const payload = {
        rider_id: riderId,
        movement_type: movementType,
        amount,
        description,
        linked_orders: Array.from(window.selectedPendingOrders || [])
    };

    try {
        const url = id ? `${API_BASE}/api/financial/rider-cash/${id}` : `${API_BASE}/api/financial/rider-cash`;
        const method = id ? 'PUT' : 'POST';
        
        const response = await fetch(url, {
            method,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', id ? 'Rider cash movement updated' : 'Cash movement recorded successfully');
            closeModal('riderCashModal');
            loadRiderCash();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error recording rider cash:', error);
        showError('Error', 'Failed to record cash movement');
    }
}

async function createStoreSettlement() {
    const form = document.getElementById('storeSettlementForm');
    if (form) {
        form.reset();
        // Set default dates for the settlement period
        setDatesForPeriod('month', 'periodFrom', 'periodTo');
    }
    const idInput = document.getElementById('storeSettlementId');
    if (idInput) idInput.value = '';

    document.querySelector('#storeSettlementModal h2').textContent = 'Create Store Settlement';
    document.querySelector('#storeSettlementModal .btn-primary').textContent = 'Create Settlement';

    formChangedState['storeSettlementModal'] = false;
    await populateStoresDropdown();
    openModal('storeSettlementModal');
}

async function submitStoreSettlement() {
    const id = document.getElementById('storeSettlementId').value;
    const storeId = parseInt(document.getElementById('settlementStoreSelect').value);
    const netAmount = parseFloat(document.getElementById('settlementAmount').value);
    const paymentMethod = document.getElementById('settlementPaymentMethod').value;
    const periodFrom = document.getElementById('periodFrom').value || null;
    const periodTo = document.getElementById('periodTo').value || null;

    const payload = {
        store_id: storeId,
        net_amount: netAmount,
        payment_method: paymentMethod,
        period_from: periodFrom,
        period_to: periodTo
    };

    try {
        const url = id ? `${API_BASE}/api/financial/store-settlements/${id}` : `${API_BASE}/api/financial/store-settlements`;
        const method = id ? 'PUT' : 'POST';

        const response = await fetch(url, {
            method,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', id ? 'Settlement updated' : 'Settlement created successfully');
            closeModal('storeSettlementModal');
            loadStoreSettlements();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error submitting settlement:', error);
        showError('Error', 'Failed to save settlement');
    }
}

async function editStoreSettlement(id) {
    const settlement = currentStoreSettlements.find(s => s.id === id);
    if (!settlement) return;

    document.getElementById('storeSettlementId').value = settlement.id;
    
    document.getElementById('settlementAmount').value = settlement.net_amount;
    document.getElementById('settlementPaymentMethod').value = settlement.payment_method;
    
    if (settlement.period_from) {
        document.getElementById('periodFrom').value = settlement.period_from.split('T')[0];
    }
    if (settlement.period_to) {
        document.getElementById('periodTo').value = settlement.period_to.split('T')[0];
    }

    document.querySelector('#storeSettlementModal h2').textContent = 'Edit Store Settlement';
    document.querySelector('#storeSettlementModal .btn-primary').textContent = 'Update Settlement';

    formChangedState['storeSettlementModal'] = false;
    await populateStoresDropdown();
    document.getElementById('settlementStoreSelect').value = settlement.store_id;
    openModal('storeSettlementModal');
}

function createExpense() {
    const form = document.getElementById('expenseForm');
    if (form) form.reset();
    const idInput = document.getElementById('expenseId');
    if (idInput) idInput.value = '';

    document.querySelector('#expenseModal h2').textContent = 'Record Expense';
    document.querySelector('#expenseModal .btn-primary').textContent = 'Record Expense';

    formChangedState['expenseModal'] = false;
    openModal('expenseModal');
}

async function submitExpense() {
    const id = document.getElementById('expenseId').value;
    const category = document.getElementById('expenseCategory').value;
    const description = document.getElementById('expenseDescription').value;
    const amount = parseFloat(document.getElementById('expenseAmount').value);
    const vendorName = document.getElementById('vendorName').value;
    const paymentMethod = document.getElementById('expensePaymentMethod').value;

    const payload = {
        category,
        description,
        amount,
        vendor_name: vendorName,
        payment_method: paymentMethod
    };

    try {
        const url = id ? `${API_BASE}/api/financial/expenses/${id}` : `${API_BASE}/api/financial/expenses`;
        const method = id ? 'PUT' : 'POST';

        const response = await fetch(url, {
            method,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', id ? 'Expense updated' : 'Expense recorded successfully');
            closeModal('expenseModal');
            loadExpenses();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error submitting expense:', error);
        showError('Error', 'Failed to save expense');
    }
}

function editExpense(id) {
    const expense = currentExpenses.find(e => e.id === id);
    if (!expense) return;

    document.getElementById('expenseId').value = expense.id;
    document.getElementById('expenseCategory').value = expense.category;
    document.getElementById('expenseDescription').value = expense.description || '';
    document.getElementById('expenseAmount').value = expense.amount;
    document.getElementById('vendorName').value = expense.vendor_name || '';
    document.getElementById('expensePaymentMethod').value = expense.payment_method;

    document.querySelector('#expenseModal h2').textContent = 'Edit Expense';
    document.querySelector('#expenseModal .btn-primary').textContent = 'Update Expense';

    formChangedState['expenseModal'] = false;
    openModal('expenseModal');
}

async function approvePaymentVoucher(id) {
    try {
        const response = await fetch(`${API_BASE}/api/financial/payment-vouchers/${id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ status: 'approved' })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Payment voucher approved');
            loadPaymentVouchers();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error approving payment voucher:', error);
        showError('Error', 'Failed to approve payment voucher');
    }
}

async function approveReceiptVoucher(id) {
    try {
        const response = await fetch(`${API_BASE}/api/financial/receipt-vouchers/${id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ status: 'approved' })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Receipt voucher approved');
            loadReceiptVouchers();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error approving receipt voucher:', error);
        showError('Error', 'Failed to approve receipt voucher');
    }
}

async function approveRiderCash(id) {
    try {
        const response = await fetch(`${API_BASE}/api/financial/rider-cash/${id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ status: 'approved' })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Rider cash movement approved');
            loadRiderCash();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error approving rider cash:', error);
        showError('Error', 'Failed to approve rider cash');
    }
}

async function approveStoreSettlement(id) {
    try {
        const response = await fetch(`${API_BASE}/api/financial/store-settlements/${id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ status: 'approved' })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Store settlement approved');
            loadStoreSettlements();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error approving store settlement:', error);
        showError('Error', 'Failed to approve store settlement');
    }
}

async function approveExpense(id) {
    try {
        const response = await fetch(`${API_BASE}/api/financial/expenses/${id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ status: 'approved' })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Expense approved');
            loadExpenses();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error approving expense:', error);
        showError('Error', 'Failed to approve expense');
    }
}

async function payExpense(id) {
    if (!confirm('Are you sure you want to mark this expense as PAID? This will record a financial transaction.')) return;
    
    try {
        const response = await fetch(`${API_BASE}/api/financial/expenses/${id}`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify({ status: 'paid' })
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Expense marked as PAID');
            loadExpenses();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error paying expense:', error);
        showError('Error', 'Failed to mark expense as paid');
    }
}

function generateFinancialReport() {
    document.getElementById('generateReportForm').reset();
    
    // Set default dates for the report period
    setDatesForPeriod('month', 'reportPeriodFrom', 'reportPeriodTo');

    const reportType = document.getElementById('reportTypeFilter')?.value || 'monthly_summary';
    document.getElementById('reportTypeModal').value = reportType;
    populateReportRidersDropdown(); // Populate riders when modal opens
    populateReportStoresDropdown(); // Populate stores when modal opens
    
    // Trigger change event to set initial visibility
    const reportTypeModal = document.getElementById('reportTypeModal');
    if (reportTypeModal) {
        reportTypeModal.dispatchEvent(new Event('change'));
    }
    
    openModal('generateReportModal');
}

async function populateReportStoresDropdown() {
    try {
        const response = await fetch(`${API_BASE}/api/stores`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        
        const select = document.getElementById('reportStoreSelect');
        if (select && data.stores) {
            select.innerHTML = '<option value="">All Stores</option>';
            data.stores.forEach(store => {
                const option = document.createElement('option');
                option.value = store.id;
                option.textContent = store.name;
                select.appendChild(option);
            });
        }
    } catch (error) {
        console.error('Error populating report stores dropdown:', error);
    }
}

async function populateReportRidersDropdown() {
    try {
        const response = await fetch(`${API_BASE}/api/riders`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        
        const select = document.getElementById('reportRiderSelect');
        if (select && data.riders) {
            select.innerHTML = '<option value="">All Riders</option>';
            data.riders.forEach(rider => {
                const option = document.createElement('option');
                option.value = rider.id;
                option.textContent = `${rider.first_name} ${rider.last_name} (${rider.phone})`;
                select.appendChild(option);
            });
        }
    } catch (error) {
        console.error('Error populating report riders dropdown:', error);
    }
}

async function submitGenerateReport() {
    const reportType = document.getElementById('reportTypeModal').value;
    const periodFromInput = document.getElementById('reportPeriodFrom').value;
    const periodToInput = document.getElementById('reportPeriodTo').value;
    const riderId = document.getElementById('reportRiderSelect')?.value;
    const storeId = document.getElementById('reportStoreSelect')?.value;

    const payload = {
        report_type: reportType
    };

    if (periodFromInput) {
        payload.period_from = periodFromInput;
    }
    if (periodToInput) {
        payload.period_to = periodToInput;
    }
    if (riderId && (
        reportType === 'rider_fuel_report' ||
        reportType === 'rider_cash_report' ||
        reportType === 'rider_orders_report' ||
        reportType === 'rider_payments_report' ||
        reportType === 'rider_receivings_report' ||
        reportType === 'rider_petrol_report' ||
        reportType === 'rider_daily_mileage_report' ||
        reportType === 'rider_daily_activity_report' ||
        reportType === 'rider_day_closing_report' ||
        reportType === 'order_wise_sale_summary'
    )) {
        payload.rider_id = riderId;
    }
    if (storeId && reportType === 'order_wise_sale_summary') {
        payload.store_id = storeId;
    }

    // Always default to preview first
    payload.preview = true;

    try {
        const response = await fetch(`${API_BASE}/api/financial/reports/generate`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        if (data.success) {
            closeModal('generateReportModal');
            
            // Show preview in the View Modal, but with extra controls
            // Add the report to currentReports temporarily so viewReport works
            const tempReport = data.report;
            // Ensure ID is unique/dummy if needed, though viewReport uses ID lookup. 
            // We'll modify viewReport or just push it.
            // Actually, viewReport expects an ID. Let's make it flexible.
            
            // Add to list but mark as preview
            tempReport.id = 'preview_temp';
            const existingIndex = currentReports.findIndex(r => r.id === 'preview_temp');
            if (existingIndex >= 0) {
                currentReports[existingIndex] = tempReport;
            } else {
                currentReports.push(tempReport);
            }
            
            // Call view report
            viewReport('preview_temp');
            
            // Update the modal footer to show "Save" button
            setTimeout(() => {
                const footer = document.querySelector('#viewReportModal .modal-footer') || document.querySelector('#reportViewModal .modal-footer');
                if (footer) {
                    // Remove existing Save button if any
                    const existingSave = document.getElementById('btnSaveReport');
                    if (existingSave) existingSave.remove();
                    
                    const saveBtn = document.createElement('button');
                    saveBtn.id = 'btnSaveReport';
                    saveBtn.type = 'button';
                    saveBtn.className = 'btn btn-success report-action-btn report-modal-action-btn';
                    saveBtn.innerHTML = 'Save Report';
                    saveBtn.onclick = () => saveGeneratedReport(payload); // Pass original payload without preview flag
                    
                    // Insert before Close button
                    footer.insertBefore(saveBtn, footer.firstChild);
                }
            }, 500);

        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error generating report:', error);
        showError('Error', 'Failed to generate report');
    }
}

async function saveGeneratedReport(payload) {
    // Remove preview flag to actually save
    const savePayload = { ...payload };
    delete savePayload.preview;
    
    try {
        const response = await fetch(`${API_BASE}/api/financial/reports/generate`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}`
            },
            body: JSON.stringify(savePayload)
        });

        const data = await response.json();
        if (data.success) {
            showSuccess('Success', 'Report saved successfully');
            // Close the view modal
            const modalId = document.getElementById('viewReportModal') ? 'viewReportModal' : 'reportViewModal';
            closeModal(modalId);
            // Refresh list
            loadFinancialReports();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error saving report:', error);
        showError('Error', 'Failed to save report');
    }
}

function generatePDF(reportId) {
    const report = currentReports.find(r => r.id === reportId);
    if (!report) return;

    // Check if jsPDF is loaded
    if (!window.jspdf) {
        alert('PDF generator library not loaded. Please refresh the page.');
        return;
    }

    const { jsPDF } = window.jspdf;
    const doc = new jsPDF();

    // Title
    doc.setFontSize(20);
    doc.text('ServeNow Financial Report', 14, 22);
    
    // Metadata
    doc.setFontSize(10);
    doc.setTextColor(100);
    doc.text(`Report #: ${report.report_number}`, 14, 32);
    doc.text(`Type: ${report.report_type.replace(/_/g, ' ').toUpperCase()}`, 14, 37);
    doc.text(`Generated: ${new Date(report.created_at).toLocaleString()}`, 14, 42);
    if (report.period_from) {
        doc.text(`Period: ${new Date(report.period_from).toLocaleDateString()} - ${report.period_to ? new Date(report.period_to).toLocaleDateString() : 'Now'}`, 14, 47);
    }

    // Financial Summary
    doc.setFontSize(12);
    doc.setTextColor(0);
    doc.text('Financial Summary', 14, 58);
    
    doc.autoTable({
        startY: 62,
        head: [['Category', 'Amount']],
        body: [
            ['Total Income', `Rs ${parseFloat(report.total_income).toFixed(2)}`],
            ['Total Expense', `Rs ${parseFloat(report.total_expense).toFixed(2)}`],
            ['Total Settlements', `Rs ${parseFloat(report.total_commissions).toFixed(2)}`],
            ['Net Profit', `Rs ${parseFloat(report.net_profit).toFixed(2)}`]
        ],
        theme: 'striped',
        headStyles: { fillColor: [41, 128, 185] },
        styles: { fontSize: 10, cellPadding: 3 }
    });

    // Detailed Data
    let data;
    try {
        data = typeof report.data === 'string' ? JSON.parse(report.data) : report.data;
    } catch (e) { data = null; }

    if (data) {
        let startY = doc.lastAutoTable.finalY + 15;
        doc.setFontSize(12);
        
        if (data.type === 'rider_cash') {
            doc.text('Rider Cash Movements', 14, startY);
            doc.autoTable({
                startY: startY + 5,
                head: [['Rider', 'Date', 'Type', 'Amount', 'Description']],
                body: data.movements.map(m => [
                    `${m.first_name} ${m.last_name}`,
                    new Date(m.movement_date).toLocaleDateString(),
                    m.movement_type,
                    `Rs ${parseFloat(m.amount).toFixed(2)}`,
                    m.description || ''
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'rider_orders') {
            doc.text('Rider Orders Report', 14, startY);
            if (data.summary) {
                doc.setFontSize(10);
                doc.text(
                    `Total: ${data.summary.total_orders} | Delivered: ${data.summary.delivered_orders} | Active: ${data.summary.active_orders} | Cancelled: ${data.summary.cancelled_orders}`,
                    14,
                    startY + 5
                );
                startY += 10;
            }
            doc.autoTable({
                startY: startY + 5,
                head: [['Order #', 'Date', 'Rider', 'Customer', 'Status', 'Payment', 'Amount', 'Delivery']],
                body: (data.orders || []).map(o => [
                    o.order_number,
                    new Date(o.created_at).toLocaleDateString(),
                    o.rider_name || '-',
                    o.customer_name || '-',
                    o.status || '-',
                    `${o.payment_method || '-'} / ${o.payment_status || '-'}`,
                    `Rs ${parseFloat(o.total_amount || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.delivery_fee || 0).toFixed(2)}`
                ]),
                theme: 'grid',
                styles: { fontSize: 7 }
            });
        } else if (data.type === 'rider_payments') {
            doc.text('Rider Payments Report', 14, startY);
            doc.autoTable({
                startY: startY + 5,
                head: [['Rider', 'Date', 'Type', 'Amount', 'Status', 'Description']],
                body: (data.entries || []).map(e => [
                    `${e.first_name || ''} ${e.last_name || ''}`.trim(),
                    new Date(e.movement_date).toLocaleDateString(),
                    e.movement_type || '-',
                    `Rs ${parseFloat(e.amount || 0).toFixed(2)}`,
                    e.status || '-',
                    e.description || ''
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'rider_receivings') {
            doc.text('Rider Receivings Report', 14, startY);
            doc.autoTable({
                startY: startY + 5,
                head: [['Rider', 'Date', 'Type', 'Amount', 'Status', 'Description']],
                body: (data.entries || []).map(e => [
                    `${e.first_name || ''} ${e.last_name || ''}`.trim(),
                    new Date(e.movement_date).toLocaleDateString(),
                    e.movement_type || '-',
                    `Rs ${parseFloat(e.amount || 0).toFixed(2)}`,
                    e.status || '-',
                    e.description || ''
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'store_financials') {
            doc.text('Store Financials (Cost Analysis)', 14, startY);
            doc.autoTable({
                startY: startY + 5,
                head: [['Store Name', 'Total Sales', 'Total Cost', 'Est. Profit']],
                body: data.stores.map(s => [
                    s.store_name,
                    `Rs ${parseFloat(s.total_sales).toFixed(2)}`,
                    `Rs ${parseFloat(s.total_cost).toFixed(2)}`,
                    `Rs ${parseFloat(s.estimated_profit).toFixed(2)}`
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'store_settlement') {
            doc.text('Store Settlements', 14, startY);
            doc.autoTable({
                startY: startY + 5,
                head: [['Settlement #', 'Date', 'Store', 'Amount', 'Comm.', 'Status']],
                body: data.settlements.map(s => [
                    s.settlement_number,
                    new Date(s.settlement_date).toLocaleDateString(),
                    s.store_name,
                    `Rs ${parseFloat(s.net_amount).toFixed(2)}`,
                    `Rs ${parseFloat(s.commissions).toFixed(2)}`,
                    s.status
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'delivery_charges_breakdown') {
            doc.text('Delivery Charges Breakdown', 14, startY);
            
            if (data.summary) {
                doc.setFontSize(10);
                doc.text(`Total Orders: ${data.summary.total_orders} | Total Fees: Rs ${parseFloat(data.summary.total_delivery_fees).toFixed(2)}`, 14, startY + 5);
                startY += 10;
            }

            doc.autoTable({
                startY: startY + 5,
                head: [['Order #', 'Date', 'Rider', 'Store', 'Fee']],
                body: data.orders.map(o => [
                    o.order_number,
                    new Date(o.order_date).toLocaleDateString(),
                    o.rider_name,
                    o.store_names,
                    `Rs ${parseFloat(o.delivery_fee).toFixed(2)}`
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'general_voucher') {
            doc.text('Journal Vouchers', 14, startY);
            doc.autoTable({
                startY: startY + 5,
                head: [['Voucher #', 'Date', 'Description', 'Amount', 'Ref']],
                body: data.vouchers.map(v => [
                    v.voucher_number,
                    new Date(v.voucher_date).toLocaleDateString(),
                    v.description || '',
                    `Rs ${parseFloat(v.total_amount).toFixed(2)}`,
                    v.reference_number || ''
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'rider_fuel' || data.type === 'rider_petrol') {
            doc.text('Rider Fuel History', 14, startY);
            
            // Summary for Fuel
            if (data.summary) {
                doc.setFontSize(10);
                doc.text(`Total Distance: ${data.summary.total_distance} km | Total Cost: Rs ${parseFloat(data.summary.total_cost).toFixed(2)}`, 14, startY + 5);
                startY += 10;
            }

            if (data.entries) {
                doc.autoTable({
                    startY: startY + 5,
                    head: [['Rider', 'Date', 'Start', 'End', 'Dist', 'Rate', 'Cost', 'Notes']],
                    body: data.entries.map(e => [
                        `${e.first_name} ${e.last_name || ''}`,
                        new Date(e.entry_date).toLocaleDateString(),
                        e.start_meter || '-',
                        e.end_meter || '-',
                        e.distance || '0',
                        e.petrol_rate || '-',
                        `Rs ${e.fuel_cost}`,
                        e.notes || ''
                    ]),
                    theme: 'grid',
                    styles: { fontSize: 8 }
                });
            }
        } else if (data.type === 'rider_daily_mileage') {
            doc.text('Rider Daily Mileage Report', 14, startY);
            if (data.summary) {
                doc.setFontSize(10);
                doc.text(
                    `Days: ${data.summary.total_days_logged} | Distance: ${parseFloat(data.summary.total_distance || 0).toFixed(2)} km | Fuel: Rs ${parseFloat(data.summary.total_fuel_cost || 0).toFixed(2)}`,
                    14,
                    startY + 5
                );
                startY += 10;
            }
            doc.autoTable({
                startY: startY + 5,
                head: [['Date', 'Rider', 'Trips', 'Distance (km)', 'Fuel Cost']],
                body: (data.rows || []).map(r => [
                    new Date(r.mileage_date).toLocaleDateString(),
                    r.rider_name || '-',
                    r.trips_logged || 0,
                    parseFloat(r.total_distance || 0).toFixed(2),
                    `Rs ${parseFloat(r.total_fuel_cost || 0).toFixed(2)}`
                ]),
                theme: 'grid',
                styles: { fontSize: 8 }
            });
        } else if (data.type === 'rider_daily_activity') {
            doc.text('Rider Daily Activity Report', 14, startY);
            if (data.summary) {
                doc.setFontSize(10);
                doc.text(
                    `Orders: ${data.summary.total_orders} | Stores: ${data.summary.total_stores_served} | Cash Collected: Rs ${parseFloat(data.summary.total_cash_collected || 0).toFixed(2)} | Paid to Cash-only Stores: Rs ${parseFloat(data.summary.total_paid_to_cash_only_stores || 0).toFixed(2)} | Cash-only Profit: Rs ${parseFloat(data.summary.total_cash_only_profit || 0).toFixed(2)}`,
                    14,
                    startY + 5
                );
                startY += 12;
            }
            doc.autoTable({
                startY: startY + 5,
                head: [['Order #', 'Date', 'Status', 'Stores', 'Cash Collected', 'Paid to Cash-only Stores', 'Cash-only Profit']],
                body: (data.orders || []).map(o => [
                    o.order_number || '-',
                    new Date(o.created_at).toLocaleDateString(),
                    o.status || '-',
                    o.stores_count || 0,
                    `Rs ${parseFloat(o.cash_collected || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.paid_to_cash_only_stores || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.cash_only_profit || 0).toFixed(2)}`
                ]),
                theme: 'grid',
                styles: { fontSize: 7 }
            });
        } else if (data.type === 'rider_day_closing') {
            doc.text('Rider Day Closing Report', 14, startY);
            if (data.summary) {
                doc.setFontSize(10);
                doc.text(
                    `Days: ${data.summary.days} | Taken: Rs ${parseFloat(data.summary.taken_total || 0).toFixed(2)} | Given: Rs ${parseFloat(data.summary.given_total || 0).toFixed(2)} | Net In Hand: Rs ${parseFloat(data.summary.net_in_hand || 0).toFixed(2)}`,
                    14,
                    startY + 5
                );
                startY += 12;
            }
            doc.autoTable({
                startY: startY + 5,
                head: [['Date', 'Rider', 'Cash Collected', 'Advance', 'Settlement', 'Store Pay', 'Fuel', 'Submit', 'Taken', 'Given', 'Net']],
                body: (data.rows || []).map(r => [
                    new Date(r.closing_date).toLocaleDateString(),
                    r.rider_name || '-',
                    `Rs ${parseFloat(r.cash_collection || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.office_advance || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.office_settlement || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.store_payment || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.fuel_payment || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.cash_submission || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.taken_total || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.given_total || 0).toFixed(2)}`,
                    `Rs ${parseFloat(r.net_in_hand || 0).toFixed(2)}`
                ]),
                theme: 'grid',
                styles: { fontSize: 7 }
            });
        } else if (data.type === 'order_profit') {
            doc.text('Order Profit Report', 14, startY);
            if (data.summary) {
                doc.setFontSize(10);
                doc.text(
                    `Orders: ${data.summary.total_orders} | Bill: Rs ${parseFloat(data.summary.bill_total || 0).toFixed(2)} | Delivery: Rs ${parseFloat(data.summary.delivery_fee || 0).toFixed(2)} | Item Profit: Rs ${parseFloat(data.summary.item_profit || 0).toFixed(2)} | Overall Profit: Rs ${parseFloat(data.summary.overall_profit || 0).toFixed(2)} | Paid to Store: Rs ${parseFloat(data.summary.paid_to_store || 0).toFixed(2)}`,
                    14,
                    startY + 5
                );
                startY += 12;
            }
            doc.autoTable({
                startY: startY + 5,
                head: [['Order #', 'Date', 'Bill Total', 'Delivery Fee', 'Item Profit', 'Overall Profit', 'Paid to Store', 'Expected Store Pay']],
                body: (data.orders || []).map(o => [
                    o.order_number || '-',
                    new Date(o.created_at).toLocaleDateString(),
                    `Rs ${parseFloat(o.bill_total || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.delivery_fee || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.item_profit || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.overall_profit || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.paid_to_store || 0).toFixed(2)}`,
                    `Rs ${parseFloat(o.paid_to_store_expected || 0).toFixed(2)}`
                ]),
                theme: 'grid',
                styles: { fontSize: 7 }
            });
        } else if (data.type === 'comprehensive_report') {
            doc.text('Comprehensive Transaction Report', 14, startY);
            
            // Add Summary Table at Top for Clarity
            if (data.summary) {
                const deliveryFees = parseFloat(data.summary.total_delivery_fees || 0);
                const itemSales = parseFloat(data.summary.total_item_sales_net || 0);
                const storeComm = parseFloat(data.summary.total_store_commission || 0);
                const totalIn = deliveryFees + itemSales;
                const netProfit = deliveryFees + storeComm;
                const netPayable = itemSales - storeComm;

                doc.autoTable({
                    startY: startY + 5,
                    head: [['Metric', 'Amount', 'Metric', 'Amount']],
                    body: [
                        ['Delivery Fees', `Rs ${deliveryFees.toFixed(2)}`, 'Item Sales (Net)', `Rs ${itemSales.toFixed(2)}`],
                        ['Store Commission', `Rs ${storeComm.toFixed(2)}`, 'Net Profit', `Rs ${netProfit.toFixed(2)}`],
                        ['Total Cash In', `Rs ${totalIn.toFixed(2)}`, 'Payable to Stores', `Rs ${netPayable.toFixed(2)}`]
                    ],
                    theme: 'grid',
                    styles: { fontSize: 9 },
                    headStyles: { fillColor: [41, 128, 185] }
                });
                startY = doc.lastAutoTable.finalY + 10;
            }

            doc.autoTable({
                startY: startY + 5,
                head: [['Date', 'Ref #', 'Type', 'Entity', 'Cat', 'In', 'Out', 'Desc']],
                body: data.transactions.map(t => [
                    new Date(t.created_at).toLocaleDateString(),
                    t.transaction_number,
                    t.transaction_type.toUpperCase(),
                    t.entity_name || t.related_entity_type || '-',
                    t.category || '-',
                    (t.transaction_type === 'income' || t.transaction_type === 'refund') ? `Rs ${parseFloat(t.amount).toFixed(2)}` : '-',
                    (t.transaction_type === 'expense' || t.transaction_type === 'settlement') ? `Rs ${parseFloat(t.amount).toFixed(2)}` : '-',
                    t.description || ''
                ]),
                theme: 'grid',
                styles: { fontSize: 7, cellPadding: 2 }
            });
        } else if (data.type === 'transaction_summary') {
            doc.text('Transaction Summary Report', 14, startY);
            
            // Summary Table
            if (data.summary) {
                doc.autoTable({
                    startY: startY + 5,
                    head: [['Metric', 'Amount', 'Metric', 'Amount']],
                    body: [
                        ['Total Income', `Rs ${parseFloat(data.summary.total_income).toFixed(2)}`, 'Total Expense', `Rs ${parseFloat(data.summary.total_expense).toFixed(2)}`],
                        ['Total Settlements', `Rs ${parseFloat(data.summary.total_settlements).toFixed(2)}`, 'Total Refunds', `Rs ${parseFloat(data.summary.total_refunds).toFixed(2)}`],
                        ['Net Cash Flow', `Rs ${parseFloat(data.summary.net_cash_flow).toFixed(2)}`, 'Total Adjustments', `Rs ${parseFloat(data.summary.total_adjustments).toFixed(2)}`]
                    ],
                    theme: 'grid',
                    styles: { fontSize: 9 },
                    headStyles: { fillColor: [41, 128, 185] }
                });
                startY = doc.lastAutoTable.finalY + 10;
            }

            doc.autoTable({
                startY: startY + 5,
                head: [['Date', 'Ref #', 'Type', 'Entity', 'In', 'Out', 'Desc']],
                body: data.transactions.map(t => {
                    const income = (t.transaction_type === 'income' || t.transaction_type === 'refund') ? parseFloat(t.amount || 0) : 0;
                    const expense = (t.transaction_type === 'expense' || t.transaction_type === 'settlement') ? parseFloat(t.amount || 0) : 0;
                    return [
                        new Date(t.created_at).toLocaleDateString(),
                        t.transaction_number,
                        t.transaction_type.toUpperCase(),
                        t.entity_name || t.related_entity_type || '-',
                        income > 0 ? `Rs ${income.toFixed(2)}` : '-',
                        expense > 0 ? `Rs ${expense.toFixed(2)}` : '-',
                        t.description || ''
                    ];
                }),
                theme: 'grid',
                styles: { fontSize: 7, cellPadding: 2 }
            });
        }
    }

    doc.save(`Report_${report.report_number}.pdf`);
}

function viewReport(reportId) {
    const report = currentReports.find(r => r.id === reportId);
    if (!report) return;

    let data;
    try {
        data = typeof report.data === 'string' ? JSON.parse(report.data) : report.data;
    } catch (e) {
        data = null;
    }

    let extraDetails = '';
    if (data && data.type === 'rider_cash') {
        extraDetails = '<h3>Rider Cash Movements</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Rider</th><th>Date</th><th>Type</th><th>Amount</th></tr></thead><tbody>';
        data.movements.forEach(m => {
            extraDetails += `<tr><td>${m.first_name} ${m.last_name}</td><td>${new Date(m.movement_date).toLocaleDateString()}</td><td>${m.movement_type}</td><td>₨ ${parseFloat(m.amount).toFixed(2)}</td></tr>`;
        });
        extraDetails += '</tbody></table></div>';
    } else if (data && data.type === 'rider_orders') {
        extraDetails = '<h3>Rider Orders Report</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Order #</th><th>Date</th><th>Rider</th><th>Customer</th><th>Status</th><th>Payment</th><th>Amount</th><th>Delivery</th></tr></thead><tbody>';
        (data.orders || []).forEach(o => {
            extraDetails += `<tr>
                <td>${o.order_number}</td>
                <td>${new Date(o.created_at).toLocaleDateString()}</td>
                <td>${o.rider_name || '-'}</td>
                <td>${o.customer_name || '-'}</td>
                <td>${o.status || '-'}</td>
                <td>${o.payment_method || '-'} / ${o.payment_status || '-'}</td>
                <td>Rs ${parseFloat(o.total_amount || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(o.delivery_fee || 0).toFixed(2)}</td>
            </tr>`;
        });
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
            extraDetails += `<div style="margin-top: 10px;"><strong>Total:</strong> ${data.summary.total_orders} | <strong>Delivered:</strong> ${data.summary.delivered_orders} | <strong>Active:</strong> ${data.summary.active_orders} | <strong>Cancelled:</strong> ${data.summary.cancelled_orders}</div>`;
        }
    } else if (data && data.type === 'rider_payments') {
        extraDetails = '<h3>Rider Payments Report</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Rider</th><th>Date</th><th>Type</th><th>Amount</th><th>Status</th><th>Description</th></tr></thead><tbody>';
        (data.entries || []).forEach(e => {
            extraDetails += `<tr>
                <td>${e.first_name || ''} ${e.last_name || ''}</td>
                <td>${new Date(e.movement_date).toLocaleDateString()}</td>
                <td>${e.movement_type || '-'}</td>
                <td>Rs ${parseFloat(e.amount || 0).toFixed(2)}</td>
                <td>${e.status || '-'}</td>
                <td>${e.description || ''}</td>
            </tr>`;
        });
        extraDetails += '</tbody></table></div>';
    } else if (data && data.type === 'rider_receivings') {
        extraDetails = '<h3>Rider Receivings Report</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Rider</th><th>Date</th><th>Type</th><th>Amount</th><th>Status</th><th>Description</th></tr></thead><tbody>';
        (data.entries || []).forEach(e => {
            extraDetails += `<tr>
                <td>${e.first_name || ''} ${e.last_name || ''}</td>
                <td>${new Date(e.movement_date).toLocaleDateString()}</td>
                <td>${e.movement_type || '-'}</td>
                <td>Rs ${parseFloat(e.amount || 0).toFixed(2)}</td>
                <td>${e.status || '-'}</td>
                <td>${e.description || ''}</td>
            </tr>`;
        });
        extraDetails += '</tbody></table></div>';
    } else if (data && data.type === 'store_financials') {
        extraDetails = '<h3>Store Financials</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Store</th><th>Sales</th><th>Cost</th><th>Profit</th></tr></thead><tbody>';
        data.stores.forEach(s => {
            extraDetails += `<tr><td>${s.store_name}</td><td>₨ ${parseFloat(s.total_sales).toFixed(2)}</td><td>₨ ${parseFloat(s.total_cost).toFixed(2)}</td><td>₨ ${parseFloat(s.estimated_profit).toFixed(2)}</td></tr>`;
        });
        extraDetails += '</tbody></table></div>';
    } else if (data && data.type === 'general_voucher') {
        extraDetails = '<h3>Journal Vouchers</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Voucher #</th><th>Date</th><th>Description</th><th>Amount</th></tr></thead><tbody>';
        data.vouchers.forEach(v => {
            extraDetails += `<tr><td>${v.voucher_number}</td><td>${new Date(v.voucher_date).toLocaleDateString()}</td><td>${v.description || '-'}</td><td>₨ ${parseFloat(v.total_amount).toFixed(2)}</td></tr>`;
        });
        extraDetails += '</tbody></table></div>';
    } else if (data && (data.type === 'rider_fuel' || data.type === 'rider_petrol')) {
        extraDetails = '<h3>Rider Fuel History</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Rider</th><th>Date</th><th>Distance</th><th>Cost</th></tr></thead><tbody>';
        if (data.entries) {
            data.entries.forEach(e => {
                extraDetails += `<tr><td>${e.first_name} ${e.last_name || ''}</td><td>${new Date(e.entry_date).toLocaleDateString()}</td><td>${e.distance} km</td><td>₨ ${parseFloat(e.fuel_cost).toFixed(2)}</td></tr>`;
            });
        }
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
            extraDetails += `<div style="margin-top: 10px;"><strong>Total Distance:</strong> ${data.summary.total_distance} km | <strong>Total Cost:</strong> ₨ ${parseFloat(data.summary.total_cost).toFixed(2)}</div>`;
        }
    } else if (data && data.type === 'rider_daily_mileage') {
        extraDetails = '<h3>Rider Daily Mileage Report</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Date</th><th>Rider</th><th>Trips</th><th>Distance (km)</th><th>Fuel Cost</th></tr></thead><tbody>';
        (data.rows || []).forEach(r => {
            extraDetails += `<tr>
                <td>${new Date(r.mileage_date).toLocaleDateString()}</td>
                <td>${r.rider_name || '-'}</td>
                <td>${r.trips_logged || 0}</td>
                <td>${parseFloat(r.total_distance || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.total_fuel_cost || 0).toFixed(2)}</td>
            </tr>`;
        });
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
            extraDetails += `<div style="margin-top: 10px;"><strong>Days Logged:</strong> ${data.summary.total_days_logged} | <strong>Total Distance:</strong> ${parseFloat(data.summary.total_distance || 0).toFixed(2)} km | <strong>Total Fuel:</strong> Rs ${parseFloat(data.summary.total_fuel_cost || 0).toFixed(2)}</div>`;
        }
    } else if (data && data.type === 'rider_daily_activity') {
        extraDetails = '<h3>Rider Daily Activity Report</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Order #</th><th>Date</th><th>Status</th><th>Stores</th><th>Cash Collected</th><th>Paid to Cash-only Stores</th><th>Cash-only Profit</th></tr></thead><tbody>';
        (data.orders || []).forEach(o => {
            extraDetails += `<tr>
                <td>${o.order_number || '-'}</td>
                <td>${new Date(o.created_at).toLocaleDateString()}</td>
                <td>${o.status || '-'}</td>
                <td>${o.stores_count || 0}</td>
                <td>Rs ${parseFloat(o.cash_collected || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(o.paid_to_cash_only_stores || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(o.cash_only_profit || 0).toFixed(2)}</td>
            </tr>`;
        });
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
            extraDetails += `<div style="margin-top: 10px;"><strong>Total Orders:</strong> ${data.summary.total_orders} | <strong>Total Stores Served:</strong> ${data.summary.total_stores_served} | <strong>Cash Collected:</strong> Rs ${parseFloat(data.summary.total_cash_collected || 0).toFixed(2)} | <strong>Paid to Cash-only Stores:</strong> Rs ${parseFloat(data.summary.total_paid_to_cash_only_stores || 0).toFixed(2)} | <strong>Cash-only Profit:</strong> Rs ${parseFloat(data.summary.total_cash_only_profit || 0).toFixed(2)}</div>`;
        }
    } else if (data && data.type === 'rider_day_closing') {
        extraDetails = '<h3>Rider Day Closing Report</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Date</th><th>Rider</th><th>Cash Collected</th><th>Advance</th><th>Settlement</th><th>Store Pay</th><th>Fuel</th><th>Submission</th><th>Taken</th><th>Given</th><th>Net In Hand</th></tr></thead><tbody>';
        (data.rows || []).forEach(r => {
            extraDetails += `<tr>
                <td>${new Date(r.closing_date).toLocaleDateString()}</td>
                <td>${r.rider_name || '-'}</td>
                <td>Rs ${parseFloat(r.cash_collection || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.office_advance || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.office_settlement || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.store_payment || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.fuel_payment || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.cash_submission || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.taken_total || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(r.given_total || 0).toFixed(2)}</td>
                <td><strong>Rs ${parseFloat(r.net_in_hand || 0).toFixed(2)}</strong></td>
            </tr>`;
        });
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
            extraDetails += `<div style="margin-top: 10px;"><strong>Days:</strong> ${data.summary.days} | <strong>Taken:</strong> Rs ${parseFloat(data.summary.taken_total || 0).toFixed(2)} | <strong>Given:</strong> Rs ${parseFloat(data.summary.given_total || 0).toFixed(2)} | <strong>Net In Hand:</strong> Rs ${parseFloat(data.summary.net_in_hand || 0).toFixed(2)}</div>`;
        }
    } else if (data && data.type === 'order_profit') {
        extraDetails = '<h3>Order Profit Report</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Order #</th><th>Date</th><th>Bill Total</th><th>Delivery Fee</th><th>Item Profit</th><th>Overall Profit</th><th>Paid to Store</th><th>Expected Store Pay</th></tr></thead><tbody>';
        (data.orders || []).forEach(o => {
            extraDetails += `<tr>
                <td>${o.order_number || '-'}</td>
                <td>${new Date(o.created_at).toLocaleDateString()}</td>
                <td>Rs ${parseFloat(o.bill_total || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(o.delivery_fee || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(o.item_profit || 0).toFixed(2)}</td>
                <td><strong>Rs ${parseFloat(o.overall_profit || 0).toFixed(2)}</strong></td>
                <td>Rs ${parseFloat(o.paid_to_store || 0).toFixed(2)}</td>
                <td>Rs ${parseFloat(o.paid_to_store_expected || 0).toFixed(2)}</td>
            </tr>`;
        });
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
            extraDetails += `<div style="margin-top: 10px;"><strong>Total Orders:</strong> ${data.summary.total_orders} | <strong>Bill Total:</strong> Rs ${parseFloat(data.summary.bill_total || 0).toFixed(2)} | <strong>Delivery Fee:</strong> Rs ${parseFloat(data.summary.delivery_fee || 0).toFixed(2)} | <strong>Item Profit:</strong> Rs ${parseFloat(data.summary.item_profit || 0).toFixed(2)} | <strong>Overall Profit:</strong> Rs ${parseFloat(data.summary.overall_profit || 0).toFixed(2)} | <strong>Paid to Store:</strong> Rs ${parseFloat(data.summary.paid_to_store || 0).toFixed(2)}</div>`;
        }
    } else if (data && data.type === 'store_settlement') {
        extraDetails = '<h3>Store Settlements</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Settlement #</th><th>Date</th><th>Store</th><th>Amount</th><th>Comm.</th><th>Status</th></tr></thead><tbody>';
        if (data.settlements) {
            data.settlements.forEach(s => {
                extraDetails += `<tr>
                    <td>${s.settlement_number}</td>
                    <td>${new Date(s.settlement_date).toLocaleDateString()}</td>
                    <td>${s.store_name}</td>
                    <td>₨ ${parseFloat(s.net_amount).toFixed(2)}</td>
                    <td>₨ ${parseFloat(s.commissions).toFixed(2)}</td>
                    <td><span class="status-${s.status}">${s.status}</span></td>
                </tr>`;
            });
        }
        extraDetails += '</tbody></table></div>';
    } else if (data && data.type === 'delivery_charges_breakdown') {
        extraDetails = '<h3>Delivery Charges Breakdown</h3><div class="report-detail-table-wrapper"><table class="report-detail-table"><thead><tr><th>Order #</th><th>Date</th><th>Rider</th><th>Store(s)</th><th>Fee</th></tr></thead><tbody>';
        if (data.orders) {
            data.orders.forEach(o => {
                extraDetails += `<tr>
                    <td>${o.order_number}</td>
                    <td>${new Date(o.order_date).toLocaleDateString()}</td>
                    <td>${o.rider_name}</td>
                    <td>${o.store_names}</td>
                    <td>₨ ${parseFloat(o.delivery_fee).toFixed(2)}</td>
                </tr>`;
            });
        }
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
            extraDetails += `<div style="margin-top: 10px;"><strong>Total Orders:</strong> ${data.summary.total_orders} | <strong>Total Delivery Fees:</strong> ₨ ${parseFloat(data.summary.total_delivery_fees).toFixed(2)}</div>`;
        }
    } else if (data && data.type === 'comprehensive_report') {
        extraDetails = '<h3>Comprehensive Transactions</h3><div class="report-detail-table-wrapper"><table class="report-detail-table" style="font-size:0.8em"><thead><tr><th>Date</th><th>Ref #</th><th>Type</th><th>Entity</th><th>In</th><th>Out</th><th>Desc</th></tr></thead><tbody>';
        if (data.transactions) {
            data.transactions.forEach(t => {
                const income = (t.transaction_type === 'income' || t.transaction_type === 'refund') ? `₨ ${parseFloat(t.amount).toFixed(2)}` : '-';
                const expense = (t.transaction_type === 'expense' || t.transaction_type === 'settlement') ? `₨ ${parseFloat(t.amount).toFixed(2)}` : '-';
                const entity = t.entity_name || t.related_entity_type || '-';
                const ref = t.reference_number_display || t.transaction_number || '-';
                
                extraDetails += `<tr>
                    <td>${new Date(t.created_at).toLocaleDateString()}</td>
                    <td>${ref}</td>
                    <td>${t.transaction_type.toUpperCase()}</td>
                    <td>${entity}</td>
                    <td style="color:green">${income}</td>
                    <td style="color:red">${expense}</td>
                    <td>${t.description || ''}</td>
                </tr>`;
            });
        }
        extraDetails += '</tbody></table></div>';
        
        // Add prominent Net Flow summary
        const flowColor = data.summary.net_flow >= 0 ? 'green' : 'red';
        extraDetails += `
            <div style="margin-top: 15px; padding: 15px; background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px;">
                <h4 style="margin: 0 0 10px 0;">Net Result Calculation</h4>
                <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; text-align: center;">
                    <div>
                        <div style="font-size: 0.8em; color: #666;">Total In (Income)</div>
                        <div style="font-size: 1.2em; font-weight: bold; color: green;">+ ₨ ${parseFloat(data.summary.total_income).toFixed(2)}</div>
                    </div>
                    <div>
                        <div style="font-size: 0.8em; color: #666;">Total Out (Expense/Settlements/Refunds)</div>
                        <div style="font-size: 1.2em; font-weight: bold; color: red;">- ₨ ${parseFloat(data.summary.total_expense + data.summary.total_settlements + data.summary.total_refunds).toFixed(2)}</div>
                    </div>
                    <div style="border-left: 2px solid #ddd;">
                        <div style="font-size: 0.8em; color: #666;">Net Result (Balance)</div>
                        <div style="font-size: 1.4em; font-weight: bold; color: ${flowColor};">₨ ${parseFloat(data.summary.net_flow).toFixed(2)}</div>
                    </div>
                </div>
                ${(data.summary.total_delivery_fees !== undefined && data.summary.total_store_commission !== undefined) ? `
                <div style="margin-top: 15px; border-top: 1px solid #ddd; padding-top: 10px; font-size: 0.9em;">
                    <div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 10px;">
                        
                        <!-- Cash In Column -->
                        <div style="background: #f9fafb; padding: 10px; border-radius: 6px;">
                            <div style="font-weight: bold; margin-bottom: 5px; color: #374151;">Cash Collected (In)</div>
                            <div style="display: flex; justify-content: space-between;"><span>Delivery Fees:</span> <span>₨ ${parseFloat(data.summary.total_delivery_fees).toFixed(2)}</span></div>
                            <div style="display: flex; justify-content: space-between;"><span>Item Sales:</span> <span>₨ ${parseFloat(data.summary.total_item_sales_net).toFixed(2)}</span></div>
                            <div style="border-top: 1px dashed #ccc; margin-top: 5px; padding-top: 5px; font-weight: bold; display: flex; justify-content: space-between;">
                                <span>Total:</span> <span>₨ ${parseFloat(data.summary.total_delivery_fees + data.summary.total_item_sales_net).toFixed(2)}</span>
                            </div>
                        </div>

                        <!-- Profit Column -->
                        <div style="background: #ecfdf5; padding: 10px; border-radius: 6px;">
                            <div style="font-weight: bold; margin-bottom: 5px; color: #065f46;">Platform Profit</div>
                            <div style="display: flex; justify-content: space-between;"><span>Delivery Profit:</span> <span>₨ ${parseFloat(data.summary.total_delivery_fees).toFixed(2)}</span></div>
                            <div style="display: flex; justify-content: space-between;"><span>Store Comm.:</span> <span>₨ ${parseFloat(data.summary.total_store_commission).toFixed(2)}</span></div>
                            <div style="border-top: 1px dashed #ccc; margin-top: 5px; padding-top: 5px; font-weight: bold; color: #059669; display: flex; justify-content: space-between;">
                                <span>Net Profit:</span> <span>₨ ${parseFloat(data.summary.estimated_gross_profit).toFixed(2)}</span>
                            </div>
                        </div>

                        <!-- Payable Column -->
                        <div style="background: #fffbeb; padding: 10px; border-radius: 6px;">
                            <div style="font-weight: bold; margin-bottom: 5px; color: #92400e;">Payable to Stores</div>
                            <div style="display: flex; justify-content: space-between;"><span>Item Sales:</span> <span>₨ ${parseFloat(data.summary.total_item_sales_net).toFixed(2)}</span></div>
                            <div style="display: flex; justify-content: space-between;"><span>Less Comm.:</span> <span>-₨ ${parseFloat(data.summary.total_store_commission).toFixed(2)}</span></div>
                            <div style="border-top: 1px dashed #ccc; margin-top: 5px; padding-top: 5px; font-weight: bold; color: #b45309; display: flex; justify-content: space-between;">
                                <span>Net Payable:</span> <span>₨ ${parseFloat(data.summary.total_item_sales_net - data.summary.total_store_commission).toFixed(2)}</span>
                            </div>
                        </div>

                    </div>
                </div>` : ''}
            </div>
        `;
    } else if (data && data.type === 'transaction_summary') {
        extraDetails = '<h3>Transaction Summary</h3><div class="report-detail-table-wrapper"><table class="report-detail-table" style="font-size:0.8em"><thead><tr><th>Date</th><th>Ref #</th><th>Type</th><th>Entity</th><th>In</th><th>Out</th><th>Desc</th></tr></thead><tbody>';
        if (data.transactions) {
            data.transactions.forEach(t => {
                const income = (t.transaction_type === 'income' || t.transaction_type === 'refund') ? parseFloat(t.amount || 0) : 0;
                const expense = (t.transaction_type === 'expense' || t.transaction_type === 'settlement') ? parseFloat(t.amount || 0) : 0;
                // Adjustments usually positive, treat as income or handle by sign if we had signed amounts.
                const entity = t.entity_name || t.related_entity_type || '-';
                const ref = t.transaction_number || '-';
                
                extraDetails += `<tr>
                    <td>${new Date(t.created_at).toLocaleDateString()}</td>
                    <td>${ref}</td>
                    <td><span class="badge badge-${t.transaction_type}">${t.transaction_type}</span></td>
                    <td>${entity}</td>
                    <td style="color:green">${income > 0 ? '₨ ' + income.toFixed(2) : '-'}</td>
                    <td style="color:red">${expense > 0 ? '₨ ' + expense.toFixed(2) : '-'}</td>
                    <td>${t.description || '-'}</td>
                </tr>`;
            });
        }
        extraDetails += '</tbody></table></div>';
        if (data.summary) {
             const flowColor = data.summary.net_cash_flow >= 0 ? 'green' : 'red';
             extraDetails += `<div style="margin-top: 15px; padding: 15px; background: #f8f9fa; border: 1px solid #ddd; border-radius: 8px;">
                <h4 style="margin: 0 0 10px 0;">Financial Summary</h4>
                <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px;">
                    <div><strong>Total Income:</strong> <span style="color:green">₨ ${parseFloat(data.summary.total_income).toFixed(2)}</span></div>
                    <div><strong>Total Expense:</strong> <span style="color:red">₨ ${parseFloat(data.summary.total_expense).toFixed(2)}</span></div>
                    <div><strong>Net Cash Flow:</strong> <span style="color:${flowColor}; font-weight:bold">₨ ${parseFloat(data.summary.net_cash_flow).toFixed(2)}</span></div>
                    <div><strong>Settlements:</strong> ₨ ${parseFloat(data.summary.total_settlements).toFixed(2)}</div>
                    <div><strong>Refunds:</strong> ₨ ${parseFloat(data.summary.total_refunds).toFixed(2)}</div>
                    <div><strong>Adjustments:</strong> ₨ ${parseFloat(data.summary.total_adjustments).toFixed(2)}</div>
                </div>
             </div>`;
        }
    } else if (data && data.type === 'order_wise_sale_summary') {
        extraDetails = '<h3>Order Wise Sale Summary</h3><div class="report-detail-table-wrapper"><table class="report-detail-table" style="font-size:0.85em"><thead><tr><th>Order #</th><th>Items</th><th>Item Sales</th><th>Total Cost</th><th>Comm.</th><th>Del. Charges</th><th>Total Amount</th></tr></thead><tbody>';
        
        if (data.orders) {
            data.orders.forEach(o => {
                let itemsList = '';
                if (o.items && Array.isArray(o.items)) {
                    itemsList = o.items.map(i => `${i.name} x${i.qty}`).join('<br>');
                }
                
                extraDetails += `<tr>
                    <td>${o.order_number}<br><small>${new Date(o.created_at).toLocaleDateString()}</small></td>
                    <td>${itemsList}</td>
                    <td>₨ ${parseFloat(o.item_sales_gross).toFixed(2)}</td>
                    <td>₨ ${parseFloat(o.total_cost_price).toFixed(2)}</td>
                    <td>₨ ${parseFloat(o.estimated_commission).toFixed(2)}</td>
                    <td>₨ ${parseFloat(o.delivery_fee).toFixed(2)}</td>
                    <td><strong>₨ ${parseFloat(o.total_amount).toFixed(2)}</strong></td>
                </tr>`;
            });
        }
        extraDetails += '</tbody></table></div>';
        
        if (data.summary) {
             extraDetails += `<div style="margin-top: 15px; font-size: 1.0em; padding: 10px; background: #f8f9fa; border: 1px solid #ddd; border-radius: 5px;">
                <strong>Totals:</strong><br>
                Item Sales: ₨ ${parseFloat(data.summary.total_item_sales).toFixed(2)} | 
                Cost: ₨ ${parseFloat(data.summary.total_cost).toFixed(2)} | 
                Commission: ₨ ${parseFloat(data.summary.total_commission).toFixed(2)} | 
                Delivery: ₨ ${parseFloat(data.summary.total_delivery).toFixed(2)} | 
                <strong>Grand Total: ₨ ${parseFloat(data.summary.grand_total).toFixed(2)}</strong>
            </div>`;
        }
    }

    const details = `
        <div class="report-summary">
            <strong>Number:</strong> ${report.report_number}<br>
            <strong>Type:</strong> ${report.report_type.replace(/_/g, ' ')}<br>
            <strong>Period:</strong> ${report.period_from ? new Date(report.period_from).toLocaleDateString() : '-'} to ${report.period_to ? new Date(report.period_to).toLocaleDateString() : '-'}<br>
            <hr>
            <strong>Total Income:</strong> ₨ ${parseFloat(report.total_income).toFixed(2)}<br>
            <strong>Total Expense:</strong> ₨ ${parseFloat(report.total_expense).toFixed(2)}<br>
            <strong>Total Settlements:</strong> ₨ ${parseFloat(report.total_commissions).toFixed(2)}<br>
            <strong>Net Profit:</strong> ₨ ${parseFloat(report.net_profit).toFixed(2)}<br>
            <strong>Generated:</strong> ${new Date(report.created_at).toLocaleString()}
        </div>
        ${extraDetails}
    `;

    // Use the new modal for preview
    const contentDiv = document.getElementById('viewReportContent');
    if (contentDiv) {
        contentDiv.innerHTML = details;
        
        // Setup download button
        const downloadBtn = document.getElementById('viewReportDownloadBtn');
        if (downloadBtn) {
            downloadBtn.onclick = () => generatePDF(reportId);
        }
        
        openModal('viewReportModal');
    } else {
        // Fallback to dynamic modal if static one is missing
        const modalId = 'reportViewModal';
        let modal = document.getElementById(modalId);
        if (!modal) {
            modal = document.createElement('div');
            modal.id = modalId;
            modal.className = 'modal';
            modal.innerHTML = `
                <div class="modal-content" style="max-width: 800px;">
                    <div class="modal-header">
                        <h3>Report Details</h3>
                        <span class="close" onclick="document.getElementById('${modalId}').classList.remove('show')">&times;</span>
                    </div>
                    <div class="modal-body" id="${modalId}Body"></div>
                    <div class="modal-footer">
                        <button class="btn btn-secondary" onclick="document.getElementById('${modalId}').classList.remove('show')">Close</button>
                        <button class="btn btn-primary" id="${modalId}Download">Download PDF</button>
                    </div>
                </div>
            `;
            document.body.appendChild(modal);
        }
        
        document.getElementById(`${modalId}Body`).innerHTML = details;
        document.getElementById(`${modalId}Download`).onclick = () => generatePDF(reportId);
        modal.classList.add('show');
    }
}

async function editRiderCash(id) {
    const movement = currentRiderCash.find(m => m.id === id);
    if (!movement) return;

    document.getElementById('riderCashId').value = movement.id;
    document.getElementById('movementType').value = movement.movement_type;
    document.getElementById('riderCashAmountInput').value = movement.amount;
    document.getElementById('riderCashDescription').value = movement.description || '';

    document.querySelector('#riderCashModal h2').textContent = 'Edit Rider Cash Movement';
    document.querySelector('#riderCashModal .btn-primary').textContent = 'Update Movement';

    formChangedState['riderCashModal'] = false;
    await populateRidersDropdown();
    document.getElementById('riderId').value = movement.rider_id;
    openModal('riderCashModal');
}

function editTransaction(id) {
    const transaction = currentTransactions.find(t => t.id === id);
    if (!transaction) return;

    document.getElementById('transactionId').value = transaction.id;
    document.getElementById('transactionAmount').value = transaction.amount;
    document.getElementById('transactionType').value = transaction.transaction_type;
    document.getElementById('transactionDescription').value = transaction.description || '';
    document.getElementById('transactionPaymentMethod').value = transaction.payment_method;

    document.querySelector('#transactionModal h2').textContent = 'Edit Transaction';
    document.querySelector('#transactionModal .btn-primary').textContent = 'Update Transaction';

    formChangedState['transactionModal'] = false;
    openModal('transactionModal');
}

function viewTransaction(id) {
    const transaction = currentTransactions.find(t => t.id === id);
    if (transaction) {
        const details = `
            <strong>Number:</strong> ${transaction.transaction_number}<br>
            <strong>Type:</strong> ${transaction.transaction_type}<br>
            <strong>Amount:</strong> ₨ ${parseFloat(transaction.amount).toFixed(2)}<br>
            <strong>Method:</strong> ${transaction.payment_method}<br>
            <strong>Status:</strong> <span class="status-${transaction.status}">${transaction.status}</span><br>
            <strong>Description:</strong> ${transaction.description || '-'}<br>
            <strong>Date:</strong> ${new Date(transaction.created_at).toLocaleString()}
        `;
        showInfo('Transaction Details', details, 10000);
    }
}

document.addEventListener('DOMContentLoaded', function() {
    const financialPeriodFilter = document.getElementById('financialPeriodFilter');
    const refreshFinancialDashboardBtn = document.getElementById('refreshFinancialDashboardBtn');
    const transactionTypeFilter = document.getElementById('transactionTypeFilter');
    const transactionStatusFilter = document.getElementById('transactionStatusFilter');
    const clearTransactionFiltersBtn = document.getElementById('clearTransactionFiltersBtn');
    const addTransactionBtn = document.getElementById('addTransactionBtn');
    const paymentVoucherStatusFilter = document.getElementById('paymentVoucherStatusFilter');
    const clearPaymentVoucherFiltersBtn = document.getElementById('clearPaymentVoucherFiltersBtn');
    const addPaymentVoucherBtn = document.getElementById('addPaymentVoucherBtn');
    const bankPaymentVoucherStatusFilter = document.getElementById('bankPaymentVoucherStatusFilter');
    const clearBankPaymentVoucherFiltersBtn = document.getElementById('clearBankPaymentVoucherFiltersBtn');
    const addBankPaymentVoucherBtn = document.getElementById('addBankPaymentVoucherBtn');
    const receiptVoucherStatusFilter = document.getElementById('receiptVoucherStatusFilter');
    const bankReceiptVoucherStatusFilter = document.getElementById('bankReceiptVoucherStatusFilter');
    const clearBankReceiptVoucherFiltersBtn = document.getElementById('clearBankReceiptVoucherFiltersBtn');
    const addBankReceiptVoucherBtn = document.getElementById('addBankReceiptVoucherBtn');
    const clearReceiptVoucherFiltersBtn = document.getElementById('clearReceiptVoucherFiltersBtn');
    const addReceiptVoucherBtn = document.getElementById('addReceiptVoucherBtn');
    const riderCashMovementTypeFilter = document.getElementById('riderCashMovementTypeFilter');
    const riderCashStatusFilter = document.getElementById('riderCashStatusFilter');
    const clearRiderCashFiltersBtn = document.getElementById('clearRiderCashFiltersBtn');
    const addRiderCashMovementBtn = document.getElementById('addRiderCashMovementBtn');
    const storeSettlementStatusFilter = document.getElementById('storeSettlementStatusFilter');
    const clearStoreSettlementFiltersBtn = document.getElementById('clearStoreSettlementFiltersBtn');
    const addStoreSettlementBtn = document.getElementById('addStoreSettlementBtn');
    const expenseCategoryFilter = document.getElementById('expenseCategoryFilter');
    const expenseStatusFilter = document.getElementById('expenseStatusFilter');
    const clearExpenseFiltersBtn = document.getElementById('clearExpenseFiltersBtn');
    const addExpenseBtn = document.getElementById('addExpenseBtn');
    const journalVoucherStatusFilter = document.getElementById('journalVoucherStatusFilter');
    const clearJournalVoucherFiltersBtn = document.getElementById('clearJournalVoucherFiltersBtn');
    const addJournalVoucherBtn = document.getElementById('addJournalVoucherBtn');
    const reportTypeFilter = document.getElementById('reportTypeFilter');
    const generateReportBtn = document.getElementById('generateReportBtn');
    const exportReportBtn = document.getElementById('exportReportBtn');

    if (financialPeriodFilter) financialPeriodFilter.addEventListener('change', loadFinancialDashboard);
    if (refreshFinancialDashboardBtn) refreshFinancialDashboardBtn.addEventListener('click', loadFinancialDashboard);
    if (transactionTypeFilter) transactionTypeFilter.addEventListener('change', loadTransactions);
    if (transactionStatusFilter) transactionStatusFilter.addEventListener('change', loadTransactions);
    if (clearTransactionFiltersBtn) clearTransactionFiltersBtn.addEventListener('click', () => {
        if (transactionTypeFilter) transactionTypeFilter.value = '';
        if (transactionStatusFilter) transactionStatusFilter.value = '';
        loadTransactions();
    });
    if (addTransactionBtn) addTransactionBtn.addEventListener('click', createTransaction);

    if (paymentVoucherStatusFilter) paymentVoucherStatusFilter.addEventListener('change', loadPaymentVouchers);
    if (clearPaymentVoucherFiltersBtn) clearPaymentVoucherFiltersBtn.addEventListener('click', () => {
        if (paymentVoucherStatusFilter) paymentVoucherStatusFilter.value = '';
        loadPaymentVouchers();
    });
    if (addPaymentVoucherBtn) addPaymentVoucherBtn.addEventListener('click', createPaymentVoucher);

    if (bankPaymentVoucherStatusFilter) bankPaymentVoucherStatusFilter.addEventListener('change', loadBankPaymentVouchers);
    if (clearBankPaymentVoucherFiltersBtn) clearBankPaymentVoucherFiltersBtn.addEventListener('click', () => {
        if (bankPaymentVoucherStatusFilter) bankPaymentVoucherStatusFilter.value = '';
        loadBankPaymentVouchers();
    });
    if (addBankPaymentVoucherBtn) addBankPaymentVoucherBtn.addEventListener('click', createBankPaymentVoucher);

    if (receiptVoucherStatusFilter) receiptVoucherStatusFilter.addEventListener('change', loadReceiptVouchers);
    if (clearReceiptVoucherFiltersBtn) clearReceiptVoucherFiltersBtn.addEventListener('click', () => {
        if (receiptVoucherStatusFilter) receiptVoucherStatusFilter.value = '';
        loadReceiptVouchers();
    });
    if (addReceiptVoucherBtn) addReceiptVoucherBtn.addEventListener('click', createReceiptVoucher);

    if (bankReceiptVoucherStatusFilter) bankReceiptVoucherStatusFilter.addEventListener('change', loadBankReceiptVouchers);
    if (clearBankReceiptVoucherFiltersBtn) clearBankReceiptVoucherFiltersBtn.addEventListener('click', () => {
        if (bankReceiptVoucherStatusFilter) bankReceiptVoucherStatusFilter.value = '';
        loadBankReceiptVouchers();
    });
    if (addBankReceiptVoucherBtn) addBankReceiptVoucherBtn.addEventListener('click', createBankReceiptVoucher);

    if (riderCashMovementTypeFilter) riderCashMovementTypeFilter.addEventListener('change', loadRiderCash);
    if (riderCashStatusFilter) riderCashStatusFilter.addEventListener('change', loadRiderCash);
    if (clearRiderCashFiltersBtn) clearRiderCashFiltersBtn.addEventListener('click', () => {
        if (riderCashMovementTypeFilter) riderCashMovementTypeFilter.value = '';
        if (riderCashStatusFilter) riderCashStatusFilter.value = '';
        loadRiderCash();
    });
    if (addRiderCashMovementBtn) addRiderCashMovementBtn.addEventListener('click', createRiderCash);

    if (storeSettlementStatusFilter) storeSettlementStatusFilter.addEventListener('change', loadStoreSettlements);
    if (clearStoreSettlementFiltersBtn) clearStoreSettlementFiltersBtn.addEventListener('click', () => {
        if (storeSettlementStatusFilter) storeSettlementStatusFilter.value = '';
        loadStoreSettlements();
    });
    if (addStoreSettlementBtn) addStoreSettlementBtn.addEventListener('click', createStoreSettlement);

    if (expenseCategoryFilter) expenseCategoryFilter.addEventListener('change', loadExpenses);
    if (expenseStatusFilter) expenseStatusFilter.addEventListener('change', loadExpenses);
    if (clearExpenseFiltersBtn) clearExpenseFiltersBtn.addEventListener('click', () => {
        if (expenseCategoryFilter) expenseCategoryFilter.value = '';
        if (expenseStatusFilter) expenseStatusFilter.value = '';
        loadExpenses();
    });
    if (addExpenseBtn) addExpenseBtn.addEventListener('click', createExpense);

    if (journalVoucherStatusFilter) journalVoucherStatusFilter.addEventListener('change', loadJournalVouchers);
    if (clearJournalVoucherFiltersBtn) clearJournalVoucherFiltersBtn.addEventListener('click', () => {
        if (journalVoucherStatusFilter) journalVoucherStatusFilter.value = '';
        loadJournalVouchers();
    });
    if (addJournalVoucherBtn) addJournalVoucherBtn.addEventListener('click', createJournalVoucher);
    
    if (reportTypeFilter) reportTypeFilter.addEventListener('change', loadFinancialReports);
    const generateFinancialReportBtn = document.getElementById('generateFinancialReportBtn');
    if (generateFinancialReportBtn) generateFinancialReportBtn.addEventListener('click', generateFinancialReport);
    
    const reportTypeModal = document.getElementById('reportTypeModal');
    if (reportTypeModal) {
        reportTypeModal.addEventListener('change', function() {
            const riderGroup = document.getElementById('reportRiderSelectGroup');
            if (riderGroup) {
                riderGroup.style.display = (
                    this.value === 'rider_fuel_report' ||
                    this.value === 'rider_cash_report' ||
                    this.value === 'rider_orders_report' ||
                    this.value === 'rider_payments_report' ||
                    this.value === 'rider_receivings_report' ||
                    this.value === 'rider_petrol_report' ||
                    this.value === 'rider_daily_mileage_report' ||
                    this.value === 'rider_daily_activity_report' ||
                    this.value === 'rider_day_closing_report' ||
                    this.value === 'delivery_charges_breakdown' ||
                    this.value === 'order_wise_sale_summary'
                ) ? 'block' : 'none';
            }
            const storeGroup = document.getElementById('reportStoreSelectGroup');
            if (storeGroup) {
                storeGroup.style.display = (this.value === 'order_wise_sale_summary') ? 'block' : 'none';
            }
        });
    }

    const generateRiderReportBtn = document.getElementById('generateRiderReportBtn');
    if (generateRiderReportBtn) generateRiderReportBtn.addEventListener('click', loadRiderReports);

    // Setup period filters and initialize defaults
    setupPeriodFilters();

    const generateStoreReportBtn = document.getElementById('generateStoreReportBtn');
    if (generateStoreReportBtn) generateStoreReportBtn.addEventListener('click', loadStoreReports);

    const exportRiderReportBtn = document.getElementById('exportRiderReportBtn');
    if (exportRiderReportBtn) exportRiderReportBtn.addEventListener('click', exportRiderReport);

    const exportStoreReportBtn = document.getElementById('exportStoreReportBtn');
    if (exportStoreReportBtn) exportStoreReportBtn.addEventListener('click', exportStoreReport);

    if (exportReportBtn) exportReportBtn.addEventListener('click', () => {
        if (currentReports.length > 0) {
            downloadReport(currentReports[0].id);
        } else {
            showWarning('No Reports', 'No reports available to export');
        }
    });

    initializePersistentModalHandlers();
    initializeFinancialManagement();
});

function initializePersistentModalHandlers() {
    financialModalIds.forEach(modalId => {
        const modal = document.getElementById(modalId);
        if (modal) {
            modal.addEventListener('click', (e) => {
                if (e.target === modal && modal.classList.contains('show')) {
                    e.stopPropagation();
                    if (formChangedState[modalId]) {
                        showWarning('Cannot Close', 'Please use the Cancel button to close this form');
                    }
                }
            });
        }
    });
}

function initializeFinancialManagement() {
    loadPaymentVouchers();
    loadBankPaymentVouchers();
    loadReceiptVouchers();
    loadBankReceiptVouchers();
    loadJournalVouchers();
}

async function populateReportFilters() {
    // Ensure riders are loaded
    // Accessing currentRiders from admin.js scope
    if (typeof currentRiders === 'undefined' || currentRiders.length === 0) {
        if (typeof loadRiders === 'function') {
            await loadRiders();
        }
    }
    
    const riderSelect = document.getElementById('riderReportSelect');
    if (riderSelect && typeof currentRiders !== 'undefined') {
        riderSelect.innerHTML = '<option value="all">All Riders</option>';
        currentRiders.forEach(r => {
            const option = document.createElement('option');
            option.value = r.id;
            option.textContent = `${r.first_name} ${r.last_name}`;
            riderSelect.appendChild(option);
        });
    }

    // Ensure stores are loaded
    if (typeof currentStores === 'undefined' || currentStores.length === 0) {
        if (typeof loadStores === 'function') {
            await loadStores();
        }
    }

    const storeSelect = document.getElementById('storeReportSelect');
    if (storeSelect && typeof currentStores !== 'undefined') {
        storeSelect.innerHTML = '<option value="all">All Stores</option>';
        currentStores.forEach(s => {
            const option = document.createElement('option');
            option.value = s.id;
            option.textContent = s.name;
            storeSelect.appendChild(option);
        });
    }
}

// Helper to set date inputs based on period
function setDatesForPeriod(period, startEl, endEl) {
    const today = new Date();
    let startDate = new Date();
    let endDate = new Date();

    switch (period) {
        case 'daily':
        case 'today':
            startDate = today;
            endDate = today;
            break;
        case 'weekly':
        case 'week':
            // Start of week (Sunday)
            startDate.setDate(today.getDate() - today.getDay());
            // End date is Today (per user request)
            endDate = today;
            break;
        case 'monthly':
        case 'month':
            startDate = new Date(today.getFullYear(), today.getMonth(), 1);
            // End date is Today
            endDate = today;
            break;
        case 'year':
            startDate = new Date(today.getFullYear(), 0, 1);
            endDate = today;
            break;
        default:
            return;
    }

    const formatDate = (date) => {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    };
    
    const sEl = document.getElementById(startEl);
    const eEl = document.getElementById(endEl);
    if (sEl) {
        sEl.value = formatDate(startDate);
        sEl.defaultValue = sEl.value;
    }
    if (eEl) {
        eEl.value = formatDate(endDate);
        eEl.defaultValue = eEl.value;
    }
}

function initializeDateDefaults() {
    // 1. Initialize Period Selectors
    const periods = [
        { periodId: 'riderReportPeriod', startId: 'riderReportStartDate', endId: 'riderReportEndDate' },
        { periodId: 'storeReportPeriod', startId: 'storeReportStartDate', endId: 'storeReportEndDate' }
    ];
    
    periods.forEach(p => {
        const el = document.getElementById(p.periodId);
        if (el && el.value && el.value !== 'custom') {
            setDatesForPeriod(el.value, p.startId, p.endId);
        }
    });

    // 2. Initialize Standalone Date Filters (Default to Month/Today if empty)
    const defaults = [
        { startId: 'filterStartDate', endId: 'filterEndDate', type: 'month' },
        { startId: 'paymentStartDate', endId: 'paymentEndDate', type: 'month' },
        { startId: 'jnvDate', type: 'today' },
        { startId: 'reportStartDate', endId: 'reportEndDate', type: 'month' },
        { startId: 'reportPeriodFrom', endId: 'reportPeriodTo', type: 'month' },
        { startId: 'periodFrom', endId: 'periodTo', type: 'month' },
        // Fallbacks if period selector didn't set them (or doesn't exist)
        { startId: 'riderReportStartDate', endId: 'riderReportEndDate', type: 'month' },
        { startId: 'storeReportStartDate', endId: 'storeReportEndDate', type: 'month' }
    ];

    defaults.forEach(d => {
        if (d.type === 'today') {
            const el = document.getElementById(d.startId);
            if (el && !el.value) {
                el.value = new Date().toISOString().split('T')[0];
            }
        } else {
            const s = document.getElementById(d.startId);
            const e = document.getElementById(d.endId);
            // Only set if both exist and start is empty
            if (s && e && !s.value) {
                setDatesForPeriod(d.type === 'month' ? 'monthly' : 'daily', d.startId, d.endId);
            }
        }
    });
}

function setupPeriodFilters() {
    document.getElementById('riderReportPeriod')?.addEventListener('change', function() {
        if (this.value !== 'custom') {
            setDatesForPeriod(this.value, 'riderReportStartDate', 'riderReportEndDate');
        }
    });

    document.getElementById('storeReportPeriod')?.addEventListener('change', function() {
        if (this.value !== 'custom') {
            setDatesForPeriod(this.value, 'storeReportStartDate', 'storeReportEndDate');
        }
    });
    
    // Initialize defaults on load
    initializeDateDefaults();
}

async function loadRiderReports() {
    try {
        const start_date = document.getElementById('riderReportStartDate')?.value;
        const end_date = document.getElementById('riderReportEndDate')?.value;
        const rider_id = document.getElementById('riderReportSelect')?.value || 'all';
        
        const params = new URLSearchParams();
        if (start_date) params.append('start_date', start_date);
        if (end_date) params.append('end_date', end_date);
        if (rider_id) params.append('rider_id', rider_id);

        const response = await fetch(`${API_BASE}/api/financial/reports/riders-detailed?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            lastRiderData = data.riders;
            displayRiderReports(data.riders);
        }
    } catch (error) {
        console.error('Error loading rider reports:', error);
    }
}

function displayRiderReports(riders) {
    const tbody = document.getElementById('riderReportsTableBody');
    if (!tbody) return;
    tbody.innerHTML = '';

    riders.forEach(r => {
        const feesEarned = parseFloat(r.total_fees || 0);
        const cashCollection = parseFloat(r.cash_collection || 0);
        const cashSubmission = parseFloat(r.cash_submission || 0);
        const pendingCash = cashCollection - cashSubmission;

        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${r.first_name} ${r.last_name}</td>
            <td>${r.email}<br>${r.phone || '-'}</td>
            <td>${r.total_assigned}</td>
            <td>${r.total_delivered}</td>
            <td>${r.total_cancelled}</td>
            <td>₨ ${feesEarned.toFixed(2)}</td>
            <td>₨ ${cashCollection.toFixed(2)}</td>
            <td>₨ ${cashSubmission.toFixed(2)}</td>
            <td style="font-weight: bold; color: ${pendingCash > 0 ? 'red' : (pendingCash < 0 ? 'blue' : 'green')}">₨ ${pendingCash.toFixed(2)}</td>
        `;
        tbody.appendChild(row);
    });
}

async function loadStoreReports() {
    try {
        const start_date = document.getElementById('storeReportStartDate')?.value;
        const end_date = document.getElementById('storeReportEndDate')?.value;
        const store_id = document.getElementById('storeReportSelect')?.value || 'all';
        
        const params = new URLSearchParams();
        if (start_date) params.append('start_date', start_date);
        if (end_date) params.append('end_date', end_date);
        if (store_id) params.append('store_id', store_id);

        const response = await fetch(`${API_BASE}/api/financial/reports/stores-detailed?${params.toString()}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();

        if (data.success) {
            lastStoreData = data.stores;
            displayStoreReports(data.stores);
        }
    } catch (error) {
        console.error('Error loading store reports:', error);
    }
}

function displayStoreReports(stores) {
    const tbody = document.getElementById('storeReportsTableBody');
    if (!tbody) return;
    tbody.innerHTML = '';

    stores.forEach(s => {
        const earnings = parseFloat(s.total_earnings || 0);
        const paid = parseFloat(s.total_paid || 0);
        const pending = parseFloat(s.pending_settlement || 0);

        const row = document.createElement('tr');
        row.innerHTML = `
            <td>${s.name}</td>
            <td>${s.email}<br>${s.phone || '-'}</td>
            <td>${s.total_orders}</td>
            <td>₨ ${earnings.toFixed(2)}</td>
            <td>₨ ${paid.toFixed(2)}</td>
            <td style="color: ${pending > 0 ? 'orange' : 'inherit'}">₨ ${pending.toFixed(2)}</td>
        `;
        tbody.appendChild(row);
    });
}

function exportRiderReport() {
    if (!lastRiderData || lastRiderData.length === 0) {
        showWarning('No Data', 'No rider report data to export. Generate a report first.');
        return;
    }

    const headers = ['Rider Name', 'Email', 'Phone', 'Assigned', 'Delivered', 'Cancelled', 'delivery charges', 'Cash Collected', 'Cash Submitted', 'Pending Cash'];
    const rows = lastRiderData.map(r => {
        const cashCollection = parseFloat(r.cash_collection || 0);
        const cashSubmission = parseFloat(r.cash_submission || 0);
        return [
            `${r.first_name} ${r.last_name}`,
            r.email,
            r.phone || '',
            r.total_assigned,
            r.total_delivered,
            r.total_cancelled,
            parseFloat(r.total_fees || 0).toFixed(2),
            cashCollection.toFixed(2),
            cashSubmission.toFixed(2),
            (cashCollection - cashSubmission).toFixed(2)
        ];
    });

    downloadCSV('rider_financial_report.csv', headers, rows);
}

function exportStoreReport() {
    if (!lastStoreData || lastStoreData.length === 0) {
        showWarning('No Data', 'No store report data to export. Generate a report first.');
        return;
    }

    const headers = ['Store Name', 'Email', 'Phone', 'Total Orders', 'Total Earnings', 'Total Paid', 'Pending Settlement'];
    const rows = lastStoreData.map(s => [
        s.name,
        s.email,
        s.phone || '',
        s.total_orders,
        parseFloat(s.total_earnings || 0).toFixed(2),
        parseFloat(s.total_paid || 0).toFixed(2),
        parseFloat(s.pending_settlement || 0).toFixed(2)
    ]);

    downloadCSV('store_financial_report.csv', headers, rows);
}

function downloadCSV(filename, headers, rows) {
    let csvContent = "data:text/csv;charset=utf-8," 
        + headers.join(",") + "\n"
        + rows.map(e => e.map(val => `"${String(val).replace(/"/g, '""')}"`).join(",")).join("\n");

    const encodedUri = encodeURI(csvContent);
    const link = document.createElement("a");
    link.setAttribute("href", encodedUri);
    link.setAttribute("download", filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

// Order Wise Detail Summary Functions

let lastOrderDetailData = null;

async function populateOrderDetailFilters() {
    try {
        const [storesRes, ridersRes] = await Promise.all([
            fetch('/api/stores').then(res => res.json()),
            fetch('/api/riders').then(res => res.json())
        ]);

        const stores = storesRes.stores || [];
        const riders = ridersRes.riders || [];

        const storeSelect = document.getElementById('orderDetailStore');
        const riderSelect = document.getElementById('orderDetailRider');

        if (storeSelect) {
            storeSelect.innerHTML = '<option value="">All Stores</option>';
            stores.forEach(s => {
                storeSelect.innerHTML += `<option value="${s.id}">${s.name}</option>`;
            });
        }

        if (riderSelect) {
            riderSelect.innerHTML = '<option value="">All Riders</option>';
            riders.forEach(r => {
                const name = r.full_name || `${r.first_name} ${r.last_name}`;
                riderSelect.innerHTML += `<option value="${r.id}">${name}</option>`;
            });
        }
    } catch (error) {
        console.error('Error populating filters:', error);
        showError('Failed to load filter data');
    }
}

async function generateOrderWiseDetailReport() {
    const fromDate = document.getElementById('orderDetailFrom').value;
    const toDate = document.getElementById('orderDetailTo').value;
    const storeId = document.getElementById('orderDetailStore').value;
    const riderId = document.getElementById('orderDetailRider').value;

    if (!fromDate || !toDate) {
        showWarning('Validation Error', 'Please select date range');
        return;
    }

    try {
        const queryParams = new URLSearchParams({
            from: fromDate,
            to: toDate,
            store_id: storeId,
            rider_id: riderId
        });

        const response = await fetch(`/api/financial/order-wise-detail-report?${queryParams}`);
        if (!response.ok) throw new Error('Failed to fetch report');
        
        const data = await response.json();
        lastOrderDetailData = data;
        
        displayOrderDetailReport(data);
        document.getElementById('orderDetailResult').style.display = 'block';
    } catch (error) {
        console.error('Error generating report:', error);
        showError('Failed to generate report');
    }
}

function displayOrderDetailReport(data) {
    const container = document.getElementById('orderDetailPreviewContent');
    if (!data || data.length === 0) {
        container.innerHTML = '<p class="text-center">No orders found for the selected criteria.</p>';
        return;
    }

    // Calculate totals
    const totals = data.reduce((acc, order) => {
        acc.item_sales_gross += parseFloat(order.item_sales_gross || 0);
        acc.delivery_fee += parseFloat(order.delivery_fee || 0);
        acc.total_in += parseFloat(order.total_in || 0);
        acc.store_commission += parseFloat(order.store_commission || 0);
        acc.platform_profit += parseFloat(order.platform_profit || 0);
        acc.payable_to_store += parseFloat(order.payable_to_store || 0);
        return acc;
    }, {
        item_sales_gross: 0,
        delivery_fee: 0,
        total_in: 0,
        store_commission: 0,
        platform_profit: 0,
        payable_to_store: 0
    });

    let html = `
        <table class="table table-bordered table-striped" style="font-size: 0.85em;">
            <thead class="thead-dark">
                <tr>
                    <th>Date</th>
                    <th>Order #</th>
                    <th>Store</th>
                    <th>Rider</th>
                    <th class="text-right">Item Sales</th>
                    <th class="text-right">Del. Fee</th>
                    <th class="text-right">Total In</th>
                    <th class="text-right">Store Comm.</th>
                    <th class="text-right">Net Profit</th>
                    <th class="text-right">Payable to Store</th>
                </tr>
            </thead>
            <tbody>
    `;

    data.forEach(order => {
        html += `
            <tr>
                <td>${new Date(order.created_at).toLocaleDateString()}</td>
                <td>${order.order_number}</td>
                <td>${order.store_names}</td>
                <td>${order.rider_name || '-'}</td>
                <td class="text-right">Rs ${parseFloat(order.item_sales_gross).toFixed(2)}</td>
                <td class="text-right">Rs ${parseFloat(order.delivery_fee).toFixed(2)}</td>
                <td class="text-right"><strong>Rs ${parseFloat(order.total_in).toFixed(2)}</strong></td>
                <td class="text-right">Rs ${parseFloat(order.store_commission).toFixed(2)}</td>
                <td class="text-right" style="color: green;">Rs ${parseFloat(order.platform_profit).toFixed(2)}</td>
                <td class="text-right" style="color: #d35400;">Rs ${parseFloat(order.payable_to_store).toFixed(2)}</td>
            </tr>
        `;
    });

    // Totals row
    html += `
            <tr style="font-weight: bold; background-color: #f2f2f2; border-top: 2px solid #333;">
                <td colspan="4" class="text-right">TOTALS:</td>
                <td class="text-right">Rs ${totals.item_sales_gross.toFixed(2)}</td>
                <td class="text-right">Rs ${totals.delivery_fee.toFixed(2)}</td>
                <td class="text-right">Rs ${totals.total_in.toFixed(2)}</td>
                <td class="text-right">Rs ${totals.store_commission.toFixed(2)}</td>
                <td class="text-right">Rs ${totals.platform_profit.toFixed(2)}</td>
                <td class="text-right">Rs ${totals.payable_to_store.toFixed(2)}</td>
            </tr>
            </tbody>
        </table>
    `;

    container.innerHTML = html;
}

function downloadOrderWiseDetailPdf() {
    if (!lastOrderDetailData || lastOrderDetailData.length === 0) {
        showWarning('No Data', 'Please generate a report first');
        return;
    }

    const { jsPDF } = window.jspdf;
    const doc = new jsPDF('l', 'mm', 'a4'); // Landscape

    doc.setFontSize(16);
    doc.text('Order Wise Detail Summary Report', 14, 15);
    
    doc.setFontSize(10);
    const fromDate = document.getElementById('orderDetailFrom').value;
    const toDate = document.getElementById('orderDetailTo').value;
    doc.text(`Period: ${fromDate} to ${toDate}`, 14, 22);

    const headers = [['Date', 'Order #', 'Store', 'Rider', 'Item Sales', 'Del. Fee', 'Total In', 'Store Comm.', 'Net Profit', 'Payable']];
    
    const body = lastOrderDetailData.map(order => [
        new Date(order.created_at).toLocaleDateString(),
        order.order_number,
        order.store_names,
        order.rider_name || '-',
        `Rs ${parseFloat(order.item_sales_gross).toFixed(2)}`,
        `Rs ${parseFloat(order.delivery_fee).toFixed(2)}`,
        `Rs ${parseFloat(order.total_in).toFixed(2)}`,
        `Rs ${parseFloat(order.store_commission).toFixed(2)}`,
        `Rs ${parseFloat(order.platform_profit).toFixed(2)}`,
        `Rs ${parseFloat(order.payable_to_store).toFixed(2)}`
    ]);

    // Calculate totals
    const totals = lastOrderDetailData.reduce((acc, order) => {
        acc.item_sales_gross += parseFloat(order.item_sales_gross || 0);
        acc.delivery_fee += parseFloat(order.delivery_fee || 0);
        acc.total_in += parseFloat(order.total_in || 0);
        acc.store_commission += parseFloat(order.store_commission || 0);
        acc.platform_profit += parseFloat(order.platform_profit || 0);
        acc.payable_to_store += parseFloat(order.payable_to_store || 0);
        return acc;
    }, {
        item_sales_gross: 0, delivery_fee: 0, total_in: 0, store_commission: 0, platform_profit: 0, payable_to_store: 0
    });

    body.push([
        'TOTALS', '', '', '',
        `Rs ${totals.item_sales_gross.toFixed(2)}`,
        `Rs ${totals.delivery_fee.toFixed(2)}`,
        `Rs ${totals.total_in.toFixed(2)}`,
        `Rs ${totals.store_commission.toFixed(2)}`,
        `Rs ${totals.platform_profit.toFixed(2)}`,
        `Rs ${totals.payable_to_store.toFixed(2)}`
    ]);

    doc.autoTable({
        head: headers,
        body: body,
        startY: 25,
        theme: 'grid',
        styles: { fontSize: 8, cellPadding: 2 },
        headStyles: { fillColor: [41, 128, 185] },
        footStyles: { fillColor: [240, 240, 240], textColor: [0, 0, 0], fontStyle: 'bold' }
    });

    doc.save(`Order_Wise_Detail_Summary_${fromDate}_to_${toDate}.pdf`);
}
