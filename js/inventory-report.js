let currentInventoryData = null;
let currentManualSalesRows = [];
let currentStoreProductSalesRows = [];
let currentCombinedProductSalesRows = [];

function inventoryMoney(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return "N/A";
    return `PKR ${n.toFixed(2)}`;
}

function inventoryNumber(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n.toLocaleString() : "0";
}

function inventoryDateTime(value) {
    if (!value) return "-";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "-";
    return date.toLocaleString();
}

function inventoryTitleCase(value) {
    return String(value || "")
        .split("_")
        .filter(Boolean)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join(" ");
}

function openInventoryModal(modalId) {
    if (typeof showModal === "function") {
        showModal(modalId);
        return;
    }
    const modal = document.getElementById(modalId);
    if (modal) modal.classList.add("show");
}

function closeInventoryModal(modalId) {
    if (typeof hideModal === "function") {
        hideModal(modalId);
        return;
    }
    const modal = document.getElementById(modalId);
    if (modal) modal.classList.remove("show");
}

function inventoryMonetaryType(value) {
    const t = String(value || "").trim().toLowerCase();
    if (t === "manual") return "Manual";
    if (t === "percent" || t === "%") return "Percent (%)";
    if (t === "amount" || t === "fixed" || t === "fixed_amount" || t === "pkr") return "Fixed Amount (PKR)";
    return "-";
}

function inventoryMonetaryValue(type, value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return "-";
    const t = String(type || "").trim().toLowerCase();
    if (t === "manual") return inventoryMoney(n);
    if (n <= 0) return "-";
    if (t === "percent") return `${n.toFixed(2)}%`;
    if (t === "amount" || t === "fixed" || t === "fixed_amount" || t === "pkr" || !t) return inventoryMoney(n);
    return inventoryMoney(n);
}

function inventoryFinancialRule(mode) {
    const m = String(mode || "").trim().toLowerCase();
    if (m === "profit") return "Profit";
    if (m === "discount") return "Discount";
    return "-";
}

function getSelectedInventoryStoreId() {
    const el = document.getElementById("inventoryStoreFilter");
    if (!el || !el.value) return null;
    const parsed = Number.parseInt(el.value, 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function getSelectedInventoryDateRange() {
    const startDate = (document.getElementById("inventoryStartDate")?.value || "").trim();
    const endDate = (document.getElementById("inventoryEndDate")?.value || "").trim();
    return {
        startDate,
        endDate,
    };
}

function buildInventorySalesQuery() {
    const params = new URLSearchParams();
    const storeId = getSelectedInventoryStoreId();
    const { startDate, endDate } = getSelectedInventoryDateRange();

    if (storeId) params.set("store_id", String(storeId));
    if (startDate) params.set("start_date", startDate);
    if (endDate) params.set("end_date", endDate);

    const query = params.toString();
    return query ? `?${query}` : "";
}

function inventoryTodayDateValue() {
    const now = new Date();
    const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
    return local.toISOString().slice(0, 10);
}

function ensureInventoryDateDefaults() {
    const today = inventoryTodayDateValue();
    const startDateEl = document.getElementById("inventoryStartDate");
    const endDateEl = document.getElementById("inventoryEndDate");
    if (startDateEl && !startDateEl.value) startDateEl.value = today;
    if (endDateEl && !endDateEl.value) endDateEl.value = today;
}

function loadInventoryReport() {
    const apiBase = window.API_BASE || `${window.location.protocol}//${window.location.host}`;
    const token = localStorage.getItem("serveNowToken");
    const storeId = getSelectedInventoryStoreId();
    const query = storeId ? `?store_id=${encodeURIComponent(storeId)}` : "";

    fetch(`${apiBase}/api/admin/inventory-report${query}`, {
        method: "GET",
        headers: {
            Authorization: `Bearer ${token}`,
        },
    })
        .then((response) => response.json())
        .then((data) => {
            if (data.success) {
                currentInventoryData = data;
                displayInventoryReport(data);
            } else {
                showError("Inventory Report", data.message || "Failed to load inventory report");
            }
        })
        .catch((err) => {
            console.error("Error loading inventory report:", err);
            showError("Inventory Report", "Error loading inventory report");
        });
}

function loadStoreSalesReport() {
    const apiBase = window.API_BASE || `${window.location.protocol}//${window.location.host}`;
    const token = localStorage.getItem("serveNowToken");
    const query = buildInventorySalesQuery();

    fetch(`${apiBase}/api/admin/store-sales-report${query}`, {
        method: "GET",
        headers: {
            Authorization: `Bearer ${token}`,
        },
    })
        .then((response) => response.json())
        .then((data) => {
            if (data.success) {
                displayStoreSalesReport(data);
            } else {
                showError("Store Sales Report", data.message || "Failed to load store sales report");
            }
        })
        .catch((err) => {
            console.error("Error loading store sales report:", err);
            showError("Store Sales Report", "Error loading store sales report");
        });
}

function loadManualOrderSalesReport() {
    const apiBase = window.API_BASE || `${window.location.protocol}//${window.location.host}`;
    const token = localStorage.getItem("serveNowToken");
    const query = buildInventorySalesQuery();

    fetch(`${apiBase}/api/admin/manual-order-sales-report${query}`, {
        method: "GET",
        headers: {
            Authorization: `Bearer ${token}`,
        },
    })
        .then((response) => response.json())
        .then((data) => {
            if (data.success) {
                displayManualOrderSalesReport(data);
            } else {
                showError("Manual Order Product Sales Report", data.message || "Failed to load manual order product sales report");
            }
        })
        .catch((err) => {
            console.error("Error loading manual order product sales report:", err);
            showError("Manual Order Product Sales Report", "Error loading manual order product sales report");
        });
}

function loadStoreProductSalesReport() {
    const apiBase = window.API_BASE || `${window.location.protocol}//${window.location.host}`;
    const token = localStorage.getItem("serveNowToken");
    const query = buildInventorySalesQuery();

    fetch(`${apiBase}/api/admin/store-product-sales-report${query}`, {
        method: "GET",
        headers: {
            Authorization: `Bearer ${token}`,
        },
    })
        .then((response) => response.json())
        .then((data) => {
            if (data.success) {
                displayStoreProductSalesReport(data);
            } else {
                showError("Store Product Sales Report", data.message || "Failed to load store product sales report");
            }
        })
        .catch((err) => {
            console.error("Error loading store product sales report:", err);
            showError("Store Product Sales Report", "Error loading store product sales report");
        });
}

function loadCombinedProductSalesReport() {
    const apiBase = window.API_BASE || `${window.location.protocol}//${window.location.host}`;
    const token = localStorage.getItem("serveNowToken");
    const query = buildInventorySalesQuery();

    fetch(`${apiBase}/api/admin/combined-product-sales-report${query}`, {
        method: "GET",
        headers: {
            Authorization: `Bearer ${token}`,
        },
    })
        .then((response) => response.json())
        .then((data) => {
            if (data.success) {
                displayCombinedProductSalesReport(data);
            } else {
                showError("Combined Product Sales Report", data.message || "Failed to load combined product sales report");
            }
        })
        .catch((err) => {
            console.error("Error loading combined product sales report:", err);
            showError("Combined Product Sales Report", "Error loading combined product sales report");
        });
}

function populateInventoryStoreFilter(stores, selectedStoreId) {
    const select = document.getElementById("inventoryStoreFilter");
    if (!select) return;
    const prev = select.value;
    select.innerHTML = `<option value="">All Stores</option>`;
    (stores || []).forEach((store) => {
        const opt = document.createElement("option");
        opt.value = String(store.id);
        opt.textContent = `${store.name}${store.is_active ? "" : " (Inactive)"}`;
        select.appendChild(opt);
    });
    if (selectedStoreId) {
        select.value = String(selectedStoreId);
    } else if (prev && Array.from(select.options).some((o) => o.value === prev)) {
        select.value = prev;
    }
}

function displayInventoryReport(data) {
    const summary = data.summary || {};

    document.getElementById("inventoryTotalStoresCount").textContent = inventoryNumber(summary.total_stores || 0);
    document.getElementById("inventoryTotalCategoriesCount").textContent = inventoryNumber(summary.total_categories || 0);
    document.getElementById("inventoryTotalProductsCount").textContent = inventoryNumber(summary.total_products || 0);
    document.getElementById("inventoryTotalStockCount").textContent = inventoryNumber(summary.total_stock || 0);
    document.getElementById("inventoryTotalValue").textContent = inventoryMoney(summary.total_inventory_value || 0);

    const activeStores = (data.store_wise || []).filter((s) => s.is_active === true || s.is_active === 1 || s.is_active === "1").length;
    const inactiveStores = (data.store_wise || []).length - activeStores;
    document.getElementById("inventoryActiveStoresCount").textContent = inventoryNumber(activeStores);
    document.getElementById("inventoryInactiveStoresCount").textContent = inventoryNumber(inactiveStores);

    populateInventoryStoreFilter(data.stores || [], data.selected_store_id);
    displayStoreWiseInventory(data.store_wise || []);
    displayCategoryWiseInventory(data.category_wise || []);
    displayStoreCategoryBreakdown(data.store_category_breakdown || []);
    displayProductDetailInventory(data.products || []);
}

function displayStoreWiseInventory(stores) {
    const tbody = document.getElementById("storeInventoryBody");
    if (!tbody) return;
    tbody.innerHTML = "";

    (stores || []).forEach((store) => {
        const row = document.createElement("tr");
        row.innerHTML = `
            <td>${store.store_name}</td>
            <td>${inventoryNumber(store.total_products)}</td>
            <td>${inventoryNumber(store.total_stock)}</td>
            <td>${inventoryMoney(store.total_inventory_value)}</td>
        `;
        tbody.appendChild(row);
    });
}

function displayCategoryWiseInventory(categories) {
    const tbody = document.getElementById("categoryInventoryBody");
    if (!tbody) return;
    tbody.innerHTML = "";

    (categories || []).forEach((category) => {
        const row = document.createElement("tr");
        row.innerHTML = `
            <td>${category.category_name}</td>
            <td>${inventoryNumber(category.total_products)}</td>
            <td>${inventoryNumber(category.total_stock)}</td>
            <td>${inventoryMoney(category.total_inventory_value)}</td>
        `;
        tbody.appendChild(row);
    });
}

function displayStoreCategoryBreakdown(breakdown) {
    const tbody = document.getElementById("storeCategoryBreakdownBody");
    if (!tbody) return;
    tbody.innerHTML = "";

    (breakdown || []).forEach((item) => {
        if ((item.product_count || 0) <= 0 && (item.stock_quantity || 0) <= 0) return;
        const row = document.createElement("tr");
        row.innerHTML = `
            <td>${item.store_name}</td>
            <td>${item.category_name || "-"}</td>
            <td>${inventoryNumber(item.product_count)}</td>
            <td>${inventoryNumber(item.stock_quantity)}</td>
            <td>${inventoryMoney(item.inventory_value)}</td>
        `;
        tbody.appendChild(row);
    });
}

function displayProductDetailInventory(products) {
    const tbody = document.getElementById("productDetailInventoryBody");
    if (!tbody) return;
    tbody.innerHTML = "";

    (products || []).forEach((p) => {
        const statusBadge = p.is_available
            ? '<span class="status-active">Active</span>'
            : '<span class="status-inactive">Inactive</span>';
        const row = document.createElement("tr");
        row.innerHTML = `
            <td>${p.store_name}</td>
            <td>${p.category_name}</td>
            <td>${p.product_name}</td>
            <td>${p.variant_label || "-"}</td>
            <td>${inventoryNumber(p.stock_quantity)}</td>
            <td>${inventoryMoney(p.cost_price)}</td>
            <td>${inventoryMoney(p.sale_price)}</td>
            <td>${inventoryFinancialRule(p.financial_mode)}</td>
            <td>${inventoryMonetaryType(p.financial_type)}</td>
            <td>${inventoryMonetaryValue(p.financial_type, p.financial_value)}</td>
            <td>${statusBadge}</td>
        `;
        tbody.appendChild(row);
    });
}

function displayStoreSalesReport(data) {
    const tbody = document.getElementById("storeSalesBody");
    if (!tbody) return;
    tbody.innerHTML = "";

    (data.store_sales || []).forEach((store) => {
        const row = document.createElement("tr");
        row.innerHTML = `
            <td>${store.store_name}</td>
            <td>${inventoryNumber(store.total_orders)}</td>
            <td>${inventoryMoney(store.total_sales_net)}</td>
            <td>${inventoryMoney(store.average_order_value)}</td>
            <td>${inventoryNumber(store.unique_customers)}</td>
        `;
        tbody.appendChild(row);
    });
}

function displayManualOrderSalesReport(data) {
    const tbody = document.getElementById("manualSalesBody");
    const footer = document.getElementById("manualSalesFooter");
    if (!tbody) return;
    tbody.innerHTML = "";
    if (footer) footer.innerHTML = "";

    const rows = data.manual_product_sales || [];
    currentManualSalesRows = rows;
    if (!rows.length) {
        const row = document.createElement("tr");
        row.innerHTML = `<td colspan="13" style="text-align:center;">No manual-order product sales found for the selected scope.</td>`;
        tbody.appendChild(row);
        return;
    }

    rows.forEach((item) => {
        const row = document.createElement("tr");
        row.dataset.orderItemId = String(item.order_item_id || "");
        row.style.cursor = "pointer";
        row.title = "Double-click to edit sale price and cost price";
        row.innerHTML = `
            <td>${item.store_name}</td>
            <td>${item.category_name || "-"}</td>
            <td>${item.product_name}</td>
            <td>${item.order_number || item.order_numbers || "-"}</td>
            <td>${inventoryTitleCase(item.order_status || "-")}</td>
            <td>${inventoryMoney(item.cost_price ?? item.average_cost_price)}</td>
            <td>${inventoryMoney(item.sale_price ?? item.average_sale_price)}</td>
            <td>${inventoryNumber(item.total_quantity)}</td>
            <td>${inventoryMoney(item.total_cost)}</td>
            <td>${inventoryMoney(item.gross_sales)}</td>
            <td>${inventoryMoney(item.net_sales)}</td>
            <td>${inventoryMoney(item.estimated_profit)}</td>
            <td>${inventoryDateTime(item.last_sold_at)}</td>
        `;
        row.addEventListener("dblclick", () => {
            openManualSalesEditModal(item.order_item_id);
        });
        tbody.appendChild(row);
    });

    if (footer) {
        const totals = rows.reduce((acc, item) => {
            acc.costPrice += Number(item.cost_price ?? item.average_cost_price ?? 0) || 0;
            acc.salePrice += Number(item.sale_price ?? item.average_sale_price ?? 0) || 0;
            acc.qty += Number(item.total_quantity || 0) || 0;
            acc.totalCost += Number(item.total_cost || 0) || 0;
            acc.grossSales += Number(item.gross_sales || 0) || 0;
            acc.netSales += Number(item.net_sales || 0) || 0;
            acc.profit += Number(item.estimated_profit || 0) || 0;
            return acc;
        }, {
            costPrice: 0,
            salePrice: 0,
            qty: 0,
            totalCost: 0,
            grossSales: 0,
            netSales: 0,
            profit: 0,
        });

        footer.innerHTML = `
            <tr style="background:#f8fafc; font-weight:700; border-top:2px solid #cbd5e1;">
                <td colspan="5">Totals</td>
                <td>${inventoryMoney(totals.costPrice)}</td>
                <td>${inventoryMoney(totals.salePrice)}</td>
                <td>${inventoryNumber(totals.qty)}</td>
                <td>${inventoryMoney(totals.totalCost)}</td>
                <td>${inventoryMoney(totals.grossSales)}</td>
                <td>${inventoryMoney(totals.netSales)}</td>
                <td>${inventoryMoney(totals.profit)}</td>
                <td>-</td>
            </tr>
        `;
    }
}

function displayStoreProductSalesReport(data) {
    const tbody = document.getElementById("storeProductSalesBody");
    const footer = document.getElementById("storeProductSalesFooter");
    if (!tbody) return;
    tbody.innerHTML = "";
    if (footer) footer.innerHTML = "";

    const rows = data.store_product_sales || [];
    currentStoreProductSalesRows = rows;
    if (!rows.length) {
        const row = document.createElement("tr");
        row.innerHTML = `<td colspan="13" style="text-align:center;">No store product sales found for the selected scope.</td>`;
        tbody.appendChild(row);
        return;
    }

    rows.forEach((item) => {
        const row = document.createElement("tr");
        row.dataset.orderItemId = String(item.order_item_id || "");
        row.style.cursor = "pointer";
        row.title = "Double-click to edit sale price and cost price";
        row.innerHTML = `
            <td>${item.store_name}</td>
            <td>${item.category_name || "-"}</td>
            <td>${item.product_name}</td>
            <td>${item.order_number || item.order_numbers || "-"}</td>
            <td>${inventoryTitleCase(item.order_status || "-")}</td>
            <td>${inventoryMoney(item.cost_price ?? item.average_cost_price)}</td>
            <td>${inventoryMoney(item.sale_price ?? item.average_sale_price)}</td>
            <td>${inventoryNumber(item.total_quantity)}</td>
            <td>${inventoryMoney(item.total_cost)}</td>
            <td>${inventoryMoney(item.gross_sales)}</td>
            <td>${inventoryMoney(item.net_sales)}</td>
            <td>${inventoryMoney(item.estimated_profit)}</td>
            <td>${inventoryDateTime(item.last_sold_at)}</td>
        `;
        row.addEventListener("dblclick", () => {
            openStoreProductSalesEditModal(item.order_item_id);
        });
        tbody.appendChild(row);
    });

    if (footer) {
        const totals = rows.reduce((acc, item) => {
            acc.costPrice += Number(item.cost_price ?? item.average_cost_price ?? 0) || 0;
            acc.salePrice += Number(item.sale_price ?? item.average_sale_price ?? 0) || 0;
            acc.qty += Number(item.total_quantity || 0) || 0;
            acc.totalCost += Number(item.total_cost || 0) || 0;
            acc.grossSales += Number(item.gross_sales || 0) || 0;
            acc.netSales += Number(item.net_sales || 0) || 0;
            acc.profit += Number(item.estimated_profit || 0) || 0;
            return acc;
        }, {
            costPrice: 0,
            salePrice: 0,
            qty: 0,
            totalCost: 0,
            grossSales: 0,
            netSales: 0,
            profit: 0,
        });

        footer.innerHTML = `
            <tr style="background:#f8fafc; font-weight:700; border-top:2px solid #cbd5e1;">
                <td colspan="5">Totals</td>
                <td>${inventoryMoney(totals.costPrice)}</td>
                <td>${inventoryMoney(totals.salePrice)}</td>
                <td>${inventoryNumber(totals.qty)}</td>
                <td>${inventoryMoney(totals.totalCost)}</td>
                <td>${inventoryMoney(totals.grossSales)}</td>
                <td>${inventoryMoney(totals.netSales)}</td>
                <td>${inventoryMoney(totals.profit)}</td>
                <td>-</td>
            </tr>
        `;
    }
}

function displayCombinedProductSalesReport(data) {
    const tbody = document.getElementById("combinedProductSalesBody");
    const footer = document.getElementById("combinedProductSalesFooter");
    if (!tbody) return;
    tbody.innerHTML = "";
    if (footer) footer.innerHTML = "";

    const rows = data.combined_product_sales || [];
    currentCombinedProductSalesRows = rows;
    if (!rows.length) {
        const row = document.createElement("tr");
        row.innerHTML = `<td colspan="14" style="text-align:center;">No product sales found for the selected scope.</td>`;
        tbody.appendChild(row);
        return;
    }

    rows.forEach((item) => {
        const row = document.createElement("tr");
        row.dataset.orderItemId = String(item.order_item_id || "");
        row.style.cursor = "pointer";
        row.title = "Double-click to edit sale price and cost price";
        row.innerHTML = `
            <td>${inventoryTitleCase(item.sale_type || "-")}</td>
            <td>${item.store_name}</td>
            <td>${item.category_name || "-"}</td>
            <td>${item.product_name}</td>
            <td>${item.order_number || item.order_numbers || "-"}</td>
            <td>${inventoryTitleCase(item.order_status || "-")}</td>
            <td>${inventoryMoney(item.cost_price ?? item.average_cost_price)}</td>
            <td>${inventoryMoney(item.sale_price ?? item.average_sale_price)}</td>
            <td>${inventoryNumber(item.total_quantity)}</td>
            <td>${inventoryMoney(item.total_cost)}</td>
            <td>${inventoryMoney(item.gross_sales)}</td>
            <td>${inventoryMoney(item.net_sales)}</td>
            <td>${inventoryMoney(item.estimated_profit)}</td>
            <td>${inventoryDateTime(item.last_sold_at)}</td>
        `;
        row.addEventListener("dblclick", () => {
            openCombinedProductSalesEditModal(item.order_item_id);
        });
        tbody.appendChild(row);
    });

    if (footer) {
        const totals = rows.reduce((acc, item) => {
            acc.costPrice += Number(item.cost_price ?? item.average_cost_price ?? 0) || 0;
            acc.salePrice += Number(item.sale_price ?? item.average_sale_price ?? 0) || 0;
            acc.qty += Number(item.total_quantity || 0) || 0;
            acc.totalCost += Number(item.total_cost || 0) || 0;
            acc.grossSales += Number(item.gross_sales || 0) || 0;
            acc.netSales += Number(item.net_sales || 0) || 0;
            acc.profit += Number(item.estimated_profit || 0) || 0;
            return acc;
        }, {
            costPrice: 0,
            salePrice: 0,
            qty: 0,
            totalCost: 0,
            grossSales: 0,
            netSales: 0,
            profit: 0,
        });

        footer.innerHTML = `
            <tr style="background:#f8fafc; font-weight:700; border-top:2px solid #cbd5e1;">
                <td colspan="6">Totals</td>
                <td>${inventoryMoney(totals.costPrice)}</td>
                <td>${inventoryMoney(totals.salePrice)}</td>
                <td>${inventoryNumber(totals.qty)}</td>
                <td>${inventoryMoney(totals.totalCost)}</td>
                <td>${inventoryMoney(totals.grossSales)}</td>
                <td>${inventoryMoney(totals.netSales)}</td>
                <td>${inventoryMoney(totals.profit)}</td>
                <td>-</td>
            </tr>
        `;
    }
}

function fillSalesEditModal(row, options) {
    const setValue = (id, value) => {
        const el = document.getElementById(id);
        if (el) el.value = value ?? "";
    };
    const setText = (id, value) => {
        const el = document.getElementById(id);
        if (el) el.textContent = value ?? "";
    };

    setValue("manualSalesEditMode", options.mode || "manual");
    setValue("manualSalesEditOrderItemId", row.order_item_id);
    setValue("manualSalesEditOrderNumber", row.order_number || row.order_numbers || "");
    setValue("manualSalesEditStatus", inventoryTitleCase(row.order_status || ""));
    setValue("manualSalesEditStore", row.store_name || "");
    setValue("manualSalesEditProduct", row.product_name || "");
    setValue("manualSalesEditQty", row.total_quantity || 0);
    setValue("manualSalesEditSoldAt", inventoryDateTime(row.last_sold_at));
    setValue("manualSalesEditCostPrice", Number(row.cost_price ?? row.average_cost_price ?? 0).toFixed(2));
    setValue("manualSalesEditSalePrice", Number(row.sale_price ?? row.average_sale_price ?? 0).toFixed(2));
    setText("manualSalesEditModalTitle", options.title || "Edit Pricing");
    setText(
        "manualSalesEditHelpText",
        options.helpText || "Saving updates only this order line and recalculates the order total."
    );
}

function openManualSalesEditModal(orderItemId) {
    const row = currentManualSalesRows.find((item) => Number(item.order_item_id) === Number(orderItemId));
    if (!row) {
        showError("Manual Order Product Sales Report", "Could not find the selected order line.");
        return;
    }

    fillSalesEditModal(row, {
        mode: "manual",
        title: "Edit Manual Order Pricing",
        helpText: "Saving updates only this manual-order line and recalculates the order total.",
    });
    openInventoryModal("manualSalesEditModal");
}

function openStoreProductSalesEditModal(orderItemId) {
    const row = currentStoreProductSalesRows.find((item) => Number(item.order_item_id) === Number(orderItemId));
    if (!row) {
        showError("Store Product Sales Report", "Could not find the selected order line.");
        return;
    }

    fillSalesEditModal(row, {
        mode: "store",
        title: "Edit Store Sale Pricing",
        helpText: "Saving updates only this store-sale line and recalculates the order total.",
    });
    openInventoryModal("manualSalesEditModal");
}

function openCombinedProductSalesEditModal(orderItemId) {
    const row = currentCombinedProductSalesRows.find((item) => Number(item.order_item_id) === Number(orderItemId));
    if (!row) {
        showError("Combined Product Sales Report", "Could not find the selected order line.");
        return;
    }

    const isManual = String(row.sale_type || "").trim().toLowerCase() === "manual";
    fillSalesEditModal(row, {
        mode: isManual ? "manual" : "store",
        title: isManual ? "Edit Manual Order Pricing" : "Edit Store Sale Pricing",
        helpText: isManual
            ? "Saving updates only this manual-order line and recalculates the order total."
            : "Saving updates only this store-sale line and recalculates the order total.",
    });
    openInventoryModal("manualSalesEditModal");
}

async function saveManualSalesEdit() {
    const apiBase = window.API_BASE || `${window.location.protocol}//${window.location.host}`;
    const token = localStorage.getItem("serveNowToken");
    const mode = String(document.getElementById("manualSalesEditMode")?.value || "manual").trim().toLowerCase();
    const orderItemId = Number(document.getElementById("manualSalesEditOrderItemId")?.value || 0);
    const costPrice = Number(document.getElementById("manualSalesEditCostPrice")?.value || 0);
    const salePrice = Number(document.getElementById("manualSalesEditSalePrice")?.value || 0);
    const reportTitle = mode === "store" ? "Store Product Sales Report" : "Manual Order Product Sales Report";
    const endpoint = mode === "store"
        ? `${apiBase}/api/admin/store-product-sales-report/${orderItemId}`
        : `${apiBase}/api/admin/manual-order-sales-report/${orderItemId}`;

    if (!Number.isInteger(orderItemId) || orderItemId <= 0) {
        showError(reportTitle, "Invalid order line selected.");
        return;
    }
    if (!Number.isFinite(costPrice) || costPrice < 0) {
        showWarning(reportTitle, "Cost price must be a non-negative number.");
        return;
    }
    if (!Number.isFinite(salePrice) || salePrice <= 0) {
        showWarning(reportTitle, "Sale price must be greater than zero.");
        return;
    }

    try {
        const response = await fetch(endpoint, {
            method: "PUT",
            headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${token}`,
            },
            body: JSON.stringify({
                cost_price: costPrice,
                sale_price: salePrice,
            }),
        });
        const data = await response.json();

        if (!data.success) {
            showError(reportTitle, data.message || "Failed to update pricing.");
            return;
        }

        closeInventoryModal("manualSalesEditModal");
        showSuccess(reportTitle, data.message || "Pricing updated successfully.");
        loadSelectedInventoryReport();
    } catch (err) {
        console.error("Error updating sales pricing:", err);
        showError(reportTitle, "Failed to update pricing.");
    }
}

function switchInventoryReport(reportType) {
    const sections = [
        "storeReportSection",
        "categoryReportSection",
        "breakdownReportSection",
        "salesReportSection",
        "manualSalesReportSection",
        "storeProductSalesReportSection",
        "combinedProductSalesReportSection",
        "productDetailReportSection",
    ];
    sections.forEach((id) => {
        const el = document.getElementById(id);
        if (el) el.style.display = "none";
    });

    switch (reportType) {
        case "store":
            document.getElementById("storeReportSection").style.display = "block";
            break;
        case "category":
            document.getElementById("categoryReportSection").style.display = "block";
            break;
        case "breakdown":
            document.getElementById("breakdownReportSection").style.display = "block";
            break;
        case "sales":
            document.getElementById("salesReportSection").style.display = "block";
            loadStoreSalesReport();
            break;
        case "manual-sales":
            document.getElementById("manualSalesReportSection").style.display = "block";
            loadManualOrderSalesReport();
            break;
        case "store-product-sales":
            document.getElementById("storeProductSalesReportSection").style.display = "block";
            loadStoreProductSalesReport();
            break;
        case "combined-product-sales":
            document.getElementById("combinedProductSalesReportSection").style.display = "block";
            loadCombinedProductSalesReport();
            break;
        case "product-detail":
            document.getElementById("productDetailReportSection").style.display = "block";
            break;
        default:
            document.getElementById("storeReportSection").style.display = "block";
            break;
    }
}

function loadSelectedInventoryReport() {
    const activeType = (document.getElementById("inventoryReportSelect") || {}).value || "store";
    switchInventoryReport(activeType);
}

function exportInventoryReportPdf() {
    if (!window.jspdf || !window.jspdf.jsPDF) {
        showError("Inventory Report", "PDF library not loaded");
        return;
    }
    if (!currentInventoryData) {
        showWarning("Inventory Report", "Load inventory report first");
        return;
    }

    const { jsPDF } = window.jspdf;
    const doc = new jsPDF("l", "mm", "a4");
    const now = new Date();
    const reportName = "Inventory Report";
    const selectedStoreId = currentInventoryData.selected_store_id;
    const selectedStoreName = selectedStoreId
        ? ((currentInventoryData.stores || []).find((s) => Number(s.id) === Number(selectedStoreId)) || {}).name || `Store #${selectedStoreId}`
        : "All Stores";

    doc.setFont("helvetica", "bold");
    doc.setFontSize(18);
    doc.text("ServeNow", 14, 14);
    doc.setFontSize(14);
    doc.text(reportName, 14, 22);
    doc.setFont("helvetica", "normal");
    doc.setFontSize(10);
    doc.text(`Store Scope: ${selectedStoreName}`, 14, 28);
    doc.text(`Generated: ${now.toLocaleString()}`, 14, 33);

    const summary = currentInventoryData.summary || {};
    doc.setFont("helvetica", "bold");
    doc.text("Summary", 14, 41);
    doc.setFont("helvetica", "normal");
    doc.text(
        `Stores: ${inventoryNumber(summary.total_stores)} | Categories: ${inventoryNumber(summary.total_categories)} | Products: ${inventoryNumber(summary.total_products)} | Stock: ${inventoryNumber(summary.total_stock)} | Inventory Value: ${inventoryMoney(summary.total_inventory_value)}`,
        14,
        47
    );

    const activeType = (document.getElementById("inventoryReportSelect") || {}).value || "store";
    let tableHead = [];
    let tableBody = [];

    if (activeType === "category") {
        tableHead = [["Category", "Products", "Stock", "Inventory Value"]];
        tableBody = (currentInventoryData.category_wise || []).map((r) => [
            r.category_name,
            inventoryNumber(r.total_products),
            inventoryNumber(r.total_stock),
            inventoryMoney(r.total_inventory_value),
        ]);
    } else if (activeType === "breakdown") {
        tableHead = [["Store", "Category", "Products", "Stock", "Value"]];
        tableBody = (currentInventoryData.store_category_breakdown || [])
            .filter((r) => (r.product_count || 0) > 0 || (r.stock_quantity || 0) > 0)
            .map((r) => [
                r.store_name,
                r.category_name || "-",
                inventoryNumber(r.product_count),
                inventoryNumber(r.stock_quantity),
                inventoryMoney(r.inventory_value),
            ]);
    } else if (activeType === "product-detail") {
        tableHead = [["Store", "Category", "Product", "Variant", "Stock", "Cost", "Sale", "Rule", "Type", "Value", "Status"]];
        tableBody = (currentInventoryData.products || []).map((r) => [
            r.store_name,
            r.category_name,
            r.product_name,
            r.variant_label || "-",
            inventoryNumber(r.stock_quantity),
            inventoryMoney(r.cost_price),
            inventoryMoney(r.sale_price),
            inventoryFinancialRule(r.financial_mode),
            inventoryMonetaryType(r.financial_type),
            inventoryMonetaryValue(r.financial_type, r.financial_value),
            r.is_available ? "Active" : "Inactive",
        ]);
    } else if (activeType === "sales" || activeType === "manual-sales" || activeType === "store-product-sales" || activeType === "combined-product-sales") {
        showWarning("Inventory Report", "Sales report PDF export is not part of inventory PDF. Switch to an inventory view.");
        return;
    } else {
        tableHead = [["Store", "Products", "Stock", "Inventory Value"]];
        tableBody = (currentInventoryData.store_wise || []).map((r) => [
            r.store_name,
            inventoryNumber(r.total_products),
            inventoryNumber(r.total_stock),
            inventoryMoney(r.total_inventory_value),
        ]);
    }

    doc.autoTable({
        startY: 53,
        head: tableHead,
        body: tableBody,
        styles: { fontSize: 9, cellPadding: 2.5, valign: "middle" },
        headStyles: { fillColor: [26, 79, 129], textColor: [255, 255, 255], fontStyle: "bold" },
        alternateRowStyles: { fillColor: [245, 248, 252] },
        margin: { left: 10, right: 10 },
        didDrawPage: () => {
            const pageCount = doc.getNumberOfPages();
            const page = doc.internal.getCurrentPageInfo().pageNumber;
            doc.setFontSize(8);
            doc.text(`Page ${page} of ${pageCount}`, 280, 205, { align: "right" });
        },
    });

    const fileDate = now.toISOString().slice(0, 10);
    const scope = selectedStoreId ? `store_${selectedStoreId}` : "all_stores";
    doc.save(`Inventory_Report_${scope}_${fileDate}.pdf`);
}

document.addEventListener("DOMContentLoaded", () => {
    ensureInventoryDateDefaults();

    const tabLinks = document.querySelectorAll(".tab-link");
    tabLinks.forEach((link) => {
        if (link.getAttribute("data-tab") === "inventory-report") {
            link.addEventListener("click", (e) => {
                e.preventDefault();
                setTimeout(() => {
                    loadInventoryReport();
                }, 100);
            });
        }
    });

    const reportSelect = document.getElementById("inventoryReportSelect");
    if (reportSelect) {
        reportSelect.addEventListener("change", (e) => {
            switchInventoryReport(e.target.value);
        });
    }

    const applyBtn = document.getElementById("inventoryApplyFilterBtn");
    if (applyBtn) applyBtn.addEventListener("click", loadSelectedInventoryReport);

    const clearBtn = document.getElementById("inventoryClearFilterBtn");
    if (clearBtn) {
        clearBtn.addEventListener("click", () => {
            const storeFilter = document.getElementById("inventoryStoreFilter");
            if (storeFilter) storeFilter.value = "";
            const startDateEl = document.getElementById("inventoryStartDate");
            const endDateEl = document.getElementById("inventoryEndDate");
            const today = inventoryTodayDateValue();
            if (startDateEl) startDateEl.value = today;
            if (endDateEl) endDateEl.value = today;
            loadSelectedInventoryReport();
        });
    }

    const pdfBtn = document.getElementById("inventoryExportPdfBtn");
    if (pdfBtn) pdfBtn.addEventListener("click", exportInventoryReportPdf);

    const saveManualSalesEditBtn = document.getElementById("saveManualSalesEditBtn");
    if (saveManualSalesEditBtn) {
        saveManualSalesEditBtn.addEventListener("click", saveManualSalesEdit);
    }

    const manualSalesEditForm = document.getElementById("manualSalesEditForm");
    if (manualSalesEditForm) {
        manualSalesEditForm.addEventListener("submit", (event) => {
            event.preventDefault();
            saveManualSalesEdit();
        });
    }
});
