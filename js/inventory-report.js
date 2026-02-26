let currentInventoryData = null;

function inventoryMoney(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return "N/A";
    return `PKR ${n.toFixed(2)}`;
}

function inventoryNumber(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n.toLocaleString() : "0";
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

    fetch(`${apiBase}/api/admin/store-sales-report`, {
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
            <td>${inventoryMoney(store.total_sales)}</td>
            <td>${inventoryMoney(store.average_order_value)}</td>
            <td>${inventoryNumber(store.unique_customers)}</td>
        `;
        tbody.appendChild(row);
    });
}

function switchInventoryReport(reportType) {
    const sections = [
        "storeReportSection",
        "categoryReportSection",
        "breakdownReportSection",
        "salesReportSection",
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
        case "product-detail":
            document.getElementById("productDetailReportSection").style.display = "block";
            break;
        default:
            document.getElementById("storeReportSection").style.display = "block";
            break;
    }
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
    } else if (activeType === "sales") {
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
    if (applyBtn) applyBtn.addEventListener("click", loadInventoryReport);

    const clearBtn = document.getElementById("inventoryClearFilterBtn");
    if (clearBtn) {
        clearBtn.addEventListener("click", () => {
            const storeFilter = document.getElementById("inventoryStoreFilter");
            if (storeFilter) storeFilter.value = "";
            loadInventoryReport();
        });
    }

    const pdfBtn = document.getElementById("inventoryExportPdfBtn");
    if (pdfBtn) pdfBtn.addEventListener("click", exportInventoryReportPdf);
});
