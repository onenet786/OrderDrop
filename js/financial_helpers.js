
// Helper functions for dynamic payee/payer selection
async function fetchFinancialEntities(type) {
    try {
        const response = await fetch(`${API_BASE}/api/financial/entities?type=${type}`, {
            headers: { 'Authorization': `Bearer ${localStorage.getItem('serveNowToken')}` }
        });
        const data = await response.json();
        return data.success ? data.data : [];
    } catch (error) {
        console.error(`Error fetching ${type}:`, error);
        return [];
    }
}

async function updateVoucherTypeUI(type, nameInput, select, hidden, addBtn) {
    nameInput.value = '';
    if (hidden) hidden.value = '';
    select.innerHTML = '<option value="">Select...</option>';
    
    if (['store', 'rider', 'employee', 'expense', 'customer', 'bank'].includes(type)) {
        nameInput.style.display = 'none';
        nameInput.removeAttribute('required');
        select.style.display = 'block';
        select.setAttribute('required', 'true');
        
        if (addBtn) addBtn.style.display = (type === 'expense' || type === 'bank') ? 'block' : 'none';
        if (addBtn.style.display === 'block') {
            if (type === 'bank') {
                addBtn.textContent = 'Add New Bank';
                addBtn.title = 'Add New Bank';
            } else {
                addBtn.textContent = '+';
                addBtn.title = 'Add New Expense Type';
            }
        }
        
        const entities = await fetchFinancialEntities(type);
        entities.forEach(entity => {
            const option = document.createElement('option');
            option.value = entity.id; // ID for entities, Name for expense types
            option.textContent = entity.name;
            option.dataset.name = entity.name;
            select.appendChild(option);
        });
    } else {
        nameInput.style.display = 'block';
        nameInput.setAttribute('required', 'true');
        select.style.display = 'none';
        select.removeAttribute('required');
        
        if (addBtn) addBtn.style.display = 'none';
    }
}

function handleVoucherTypeChange(typeSelectId, nameInputId, selectId, hiddenId, addBtnId) {
    const typeSelect = document.getElementById(typeSelectId);
    const nameInput = document.getElementById(nameInputId);
    const select = document.getElementById(selectId);
    const hidden = document.getElementById(hiddenId);
    const addBtn = document.getElementById(addBtnId);

    if (!typeSelect || !nameInput || !select) return;

    typeSelect.addEventListener('change', async () => {
        await updateVoucherTypeUI(typeSelect.value, nameInput, select, hidden, addBtn);
    });

    select.addEventListener('change', () => {
        const selectedOption = select.options[select.selectedIndex];
        if (selectedOption.value) {
            if (hidden) hidden.value = selectedOption.value;
            nameInput.value = selectedOption.dataset.name || selectedOption.textContent;
        } else {
            if (hidden) hidden.value = '';
            nameInput.value = '';
        }
    });
    
    if (addBtn) {
        addBtn.addEventListener('click', () => {
            if (typeSelect.value === 'bank') {
                if (typeof openModal === 'function') {
                    // Explicitly set button text to ensure it's correct
                    const bankModal = document.getElementById('addBankModal');
                    if (bankModal) {
                        const btn = bankModal.querySelector('.btn-primary');
                        if (btn) btn.textContent = 'Add New Bank';
                        // Force layout update to ensure text change is rendered
                        btn.style.display = 'none';
                        btn.offsetHeight; // Trigger reflow
                        btn.style.display = '';
                    }
                    openModal('addBankModal');
                } else {
                    console.error('openModal function not found');
                }
                return;
            }

            const newType = prompt("Enter new Expense Type:");
            if (newType && newType.trim()) {
                const option = document.createElement('option');
                option.value = newType.trim();
                option.textContent = newType.trim();
                option.dataset.name = newType.trim();
                option.selected = true;
                select.appendChild(option);
                select.dispatchEvent(new Event('change'));
            }
        });
    }
}


