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
        await submitPaymentVoucher();
    });
    trackFormChanges('paymentVoucherForm', 'paymentVoucherModal');
    
    document.getElementById('receiptVoucherForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        await submitReceiptVoucher();
    });
    trackFormChanges('receiptVoucherForm', 'receiptVoucherModal');
    
    document.getElementById('transactionForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        await submitTransaction();
    });
    trackFormChanges('transactionForm', 'transactionModal');
    
    document.getElementById('riderCashForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        await submitRiderCash();
    });
    trackFormChanges('riderCashForm', 'riderCashModal');
    
    document.getElementById('storeSettlementForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        await submitStoreSettlement();
    });
    trackFormChanges('storeSettlementForm', 'storeSettlementModal');
    
    document.getElementById('expenseForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
        await submitExpense();
    });
    trackFormChanges('expenseForm', 'expenseModal');
    
    document.getElementById('journalVoucherForm')?.addEventListener('submit', async (e) => {
        e.preventDefault();
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
        row.innerHTML = `
            <td>${e.expense_number}</td>
            <td>${date}</td>
            <td>${e.category}</td>
            <td>${e.description || '-'}</td>
            <td>₨ ${parseFloat(e.amount).toFixed(2)}</td>
            <td>${e.vendor_name || '-'}</td>
            <td><span class="status-${e.status}">${e.status}</span></td>
            <td>
                <button class="btn-small btn-info" onclick="editExpense(${e.id})">Edit</button>
                <button class="btn-small btn-primary" onclick="approveExpense(${e.id})">Approve</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (expenses.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; padding: 2rem;">No expenses found</td></tr>';
    }
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
                <button class="btn-small btn-secondary" onclick="downloadReport(${r.id})">Download</button>
            </td>
        `;
        tbody.appendChild(row);
    });

    if (reports.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 2rem;">No reports found</td></tr>';
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

    const payload = {
        payee_name: payeeName,
        payee_type: payeeType,
        payee_id: (payeeType === 'expense') ? null : (payeeId || null),
        amount,
        purpose,
        description: '',
        payment_method: paymentMethod,
        check_number: null,
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
        check_number: null,
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
    openModal('riderCashModal');
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
        description
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
    if (form) form.reset();
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

function generateFinancialReport() {
    document.getElementById('generateReportForm').reset();
    const reportType = document.getElementById('reportTypeFilter')?.value || 'monthly_summary';
    document.getElementById('reportTypeModal').value = reportType;
    openModal('generateReportModal');
}

async function submitGenerateReport() {
    const reportType = document.getElementById('reportTypeModal').value;
    const periodFromInput = document.getElementById('reportPeriodFrom').value;
    const periodToInput = document.getElementById('reportPeriodTo').value;

    const payload = {
        report_type: reportType
    };

    if (periodFromInput) {
        payload.period_from = periodFromInput;
    }
    if (periodToInput) {
        payload.period_to = periodToInput;
    }

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
            showSuccess('Success', 'Report generated successfully');
            closeModal('generateReportModal');
            loadFinancialReports();
        } else {
            showError('Error', data.message);
        }
    } catch (error) {
        console.error('Error generating report:', error);
        showError('Error', 'Failed to generate report');
    }
}

function downloadReport(reportId) {
    const report = currentReports.find(r => r.id === reportId);
    if (!report) return;

    let csvRows = [
        ['Report Number', report.report_number],
        ['Report Type', report.report_type],
        ['Period From', report.period_from || '-'],
        ['Period To', report.period_to || '-'],
        ['Total Income', `₨ ${parseFloat(report.total_income).toFixed(2)}`],
        ['Total Expense', `₨ ${parseFloat(report.total_expense).toFixed(2)}`],
        ['Total Settlements', `₨ ${parseFloat(report.total_commissions).toFixed(2)}`],
        ['Net Profit', `₨ ${parseFloat(report.net_profit).toFixed(2)}`],
        ['Generated Date', new Date(report.created_at).toLocaleDateString()],
        [] // Empty row separator
    ];

    let data;
    try {
        data = typeof report.data === 'string' ? JSON.parse(report.data) : report.data;
    } catch (e) {
        data = null;
    }

    if (data && data.type === 'rider_cash') {
        csvRows.push(['Rider Cash Movements']);
        csvRows.push(['Rider', 'Date', 'Type', 'Amount', 'Description']);
        data.movements.forEach(m => {
            csvRows.push([`${m.first_name} ${m.last_name}`, new Date(m.movement_date).toLocaleDateString(), m.movement_type, m.amount, m.description || '']);
        });
    } else if (data && data.type === 'store_financials') {
        csvRows.push(['Store Financials (Cost Analysis)']);
        csvRows.push(['Store Name', 'Total Sales', 'Total Cost', 'Estimated Profit']);
        data.stores.forEach(s => {
            csvRows.push([s.store_name, s.total_sales, s.total_cost, s.estimated_profit]);
        });
    } else if (data && data.type === 'general_voucher') {
        csvRows.push(['Journal Vouchers']);
        csvRows.push(['Voucher #', 'Date', 'Description', 'Amount', 'Reference']);
        data.vouchers.forEach(v => {
            csvRows.push([v.voucher_number, new Date(v.voucher_date).toLocaleDateString(), v.description || '', v.total_amount, v.reference_number || '']);
        });
    }

    const csvContent = csvRows
        .map(row => row.map(cell => `"${(cell || '').toString().replace(/"/g, '""')}"`).join(','))
        .join('\n');

    const blob = new Blob([csvContent], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.style.display = 'none';
    a.href = url;
    a.download = `${report.report_number}.csv`;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    a.remove();
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
        extraDetails = '<h3>Rider Cash Movements</h3><div style="max-height: 300px; overflow-y: auto;"><table class="report-detail-table"><thead><tr><th>Rider</th><th>Date</th><th>Type</th><th>Amount</th></tr></thead><tbody>';
        data.movements.forEach(m => {
            extraDetails += `<tr><td>${m.first_name} ${m.last_name}</td><td>${new Date(m.movement_date).toLocaleDateString()}</td><td>${m.movement_type}</td><td>₨ ${parseFloat(m.amount).toFixed(2)}</td></tr>`;
        });
        extraDetails += '</tbody></table></div>';
    } else if (data && data.type === 'store_financials') {
        extraDetails = '<h3>Store Financials</h3><div style="max-height: 300px; overflow-y: auto;"><table class="report-detail-table"><thead><tr><th>Store</th><th>Sales</th><th>Cost</th><th>Profit</th></tr></thead><tbody>';
        data.stores.forEach(s => {
            extraDetails += `<tr><td>${s.store_name}</td><td>₨ ${parseFloat(s.total_sales).toFixed(2)}</td><td>₨ ${parseFloat(s.total_cost).toFixed(2)}</td><td>₨ ${parseFloat(s.estimated_profit).toFixed(2)}</td></tr>`;
        });
        extraDetails += '</tbody></table></div>';
    } else if (data && data.type === 'general_voucher') {
        extraDetails = '<h3>Journal Vouchers</h3><div style="max-height: 300px; overflow-y: auto;"><table class="report-detail-table"><thead><tr><th>Voucher #</th><th>Date</th><th>Description</th><th>Amount</th></tr></thead><tbody>';
        data.vouchers.forEach(v => {
            extraDetails += `<tr><td>${v.voucher_number}</td><td>${new Date(v.voucher_date).toLocaleDateString()}</td><td>${v.description || '-'}</td><td>₨ ${parseFloat(v.total_amount).toFixed(2)}</td></tr>`;
        });
        extraDetails += '</tbody></table></div>';
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

    // Create a modal instead of showInfo for better presentation of tables
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
                    <button class="btn btn-primary" id="${modalId}Download">Download CSV</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
    }
    
    document.getElementById(`${modalId}Body`).innerHTML = details;
    document.getElementById(`${modalId}Download`).onclick = () => downloadReport(reportId);
    modal.classList.add('show');
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
    
    const generateRiderReportBtn = document.getElementById('generateRiderReportBtn');
    if (generateRiderReportBtn) generateRiderReportBtn.addEventListener('click', loadRiderReports);

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

function setupPeriodFilters() {
    const setDatesForPeriod = (period, startEl, endEl) => {
        const today = new Date();
        let startDate = new Date();
        let endDate = new Date();

        switch (period) {
            case 'daily':
                startDate = today;
                endDate = today;
                break;
            case 'weekly':
                startDate.setDate(today.getDate() - today.getDay());
                endDate.setDate(startDate.getDate() + 6);
                break;
            case 'monthly':
                startDate = new Date(today.getFullYear(), today.getMonth(), 1);
                endDate = new Date(today.getFullYear(), today.getMonth() + 1, 0);
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
        document.getElementById(startEl).value = formatDate(startDate);
        document.getElementById(endEl).value = formatDate(endDate);
    };

    document.getElementById('riderReportPeriod')?.addEventListener('change', function() {
        setDatesForPeriod(this.value, 'riderReportStartDate', 'riderReportEndDate');
    });

    document.getElementById('storeReportPeriod')?.addEventListener('change', function() {
        setDatesForPeriod(this.value, 'storeReportStartDate', 'storeReportEndDate');
    });
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
