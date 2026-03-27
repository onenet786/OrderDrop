(function () {
  const API_BASE = window.location.origin;
  const palettePairs = [
    { accent: "#0f6cc9", soft: "#7ed8ff" },
    { accent: "#2e6acf", soft: "#b6e2ff" },
    { accent: "#cb7a25", soft: "#ffd57a" },
    { accent: "#9b6bff", soft: "#f1c2ff" },
    { accent: "#3b9f1e", soft: "#a7f55c" },
    { accent: "#dc2626", soft: "#ffcaa9" },
    { accent: "#0f766e", soft: "#99f6e4" },
  ];

  const state = {
    stores: [],
    filteredStores: [],
    selectedStore: null,
    selectedProducts: [],
  };

  const refs = {
    storeSearch: document.getElementById("storeSearch"),
    storeCountChip: document.getElementById("storeCountChip"),
    storeStatusBanner: document.getElementById("storeStatusBanner"),
    storeGrid: document.getElementById("storeGrid"),
    productSection: document.getElementById("productSection"),
    productSectionTitle: document.getElementById("productSectionTitle"),
    productSectionSubtitle: document.getElementById("productSectionSubtitle"),
    selectedStoreSummary: document.getElementById("selectedStoreSummary"),
    productStatusBanner: document.getElementById("productStatusBanner"),
    productGrid: document.getElementById("productGrid"),
    backToStoresBtn: document.getElementById("backToStoresBtn"),
  };

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function getImageUrl(raw) {
    const value = String(raw || "").trim();
    if (!value) return "";
    if (/^https?:\/\//i.test(value) || value.startsWith("data:")) return value;
    if (value.startsWith("//")) return `https:${value}`;
    if (value.startsWith("/")) return `${API_BASE}${value}`;
    return `${API_BASE}/${value.replace(/^\/+/, "")}`;
  }

  function isOpenStore(store) {
    const value = store && store.is_open;
    return value === true || value === 1 || String(value) === "1";
  }

  function asNumber(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  function compareStores(a, b) {
    const openCompare = Number(isOpenStore(b)) - Number(isOpenStore(a));
    if (openCompare !== 0) return openCompare;
    const ratingCompare = asNumber(b.rating) - asNumber(a.rating);
    if (ratingCompare !== 0) return ratingCompare;
    return String(a.name || "").localeCompare(String(b.name || ""));
  }

  function avatarText(value) {
    const words = String(value || "")
      .trim()
      .split(/\s+/)
      .filter(Boolean);
    if (!words.length) return "SN";
    if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
    return `${words[0][0]}${words[1][0]}`.toUpperCase();
  }

  function firstVariant(product) {
    return Array.isArray(product.size_variants) && product.size_variants.length
      ? product.size_variants[0]
      : null;
  }

  function effectivePrice(source) {
    const price = asNumber(source && source.price);
    const promo = source && source.promotional_price !== null && source.promotional_price !== undefined
      ? asNumber(source.promotional_price)
      : null;
    if (promo !== null && promo >= 0 && promo < price) return promo;
    return price;
  }

  function productSubtitle(product) {
    const variant = firstVariant(product);
    if (variant) {
      const size = String(variant.size_label || "").trim();
      const unit = String(variant.unit_name || "").trim();
      return [size, unit].filter(Boolean).join(" ") || "Default";
    }
    const description = String(product.description || "").trim();
    if (description) return description;
    const category = String(product.category_name || "").trim();
    return category || "Store product";
  }

  function variantLabels(product) {
    if (!Array.isArray(product.size_variants)) return [];
    const labels = [];
    product.size_variants.forEach((variant) => {
      const size = String(variant && variant.size_label || "").trim();
      const unit = String(variant && variant.unit_name || "").trim();
      const label = [size, unit].filter(Boolean).join(" ") || "Default";
      if (label && !labels.includes(label)) labels.push(label);
    });
    return labels;
  }

  function renderStatusBanner(target, message, type) {
    if (!target) return;
    const safeType = type === "error" ? "is-error" : "is-info";
    target.innerHTML = `
      <div class="demo-status__banner ${safeType}">
        ${escapeHtml(message)}
      </div>
    `;
  }

  function renderEmpty(target, title, subtitle) {
    if (!target) return;
    target.innerHTML = `
      <div class="demo-empty">
        <i class="fas fa-inbox"></i>
        <h3>${escapeHtml(title)}</h3>
        <p>${escapeHtml(subtitle)}</p>
      </div>
    `;
  }

  function renderAvatar(title, imageUrl) {
    if (imageUrl) {
      return `
        <div class="demo-avatar">
          <div class="demo-avatar__inner">
            <img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(title)}" />
          </div>
        </div>
      `;
    }
    return `
      <div class="demo-avatar">
        <div class="demo-avatar__inner">${escapeHtml(avatarText(title))}</div>
      </div>
    `;
  }

  function renderStoreTile(store, index) {
    const palette = palettePairs[index % palettePairs.length];
    const featured = index === 0;
    const imageUrl = getImageUrl(store.image_url);
    const footerText = String(store.delivery_time || "").trim()
      ? `${escapeHtml(store.delivery_time)} min`
      : "Preview";
    const location = String(store.location || "Unknown location");
    const open = isOpenStore(store);
    const rating = asNumber(store.rating);

    return `
      <article
        class="demo-tile ${featured ? "is-featured" : ""}"
        style="--tile-accent:${palette.accent};--tile-soft:${palette.soft};"
      >
        <div class="demo-rank">${index + 1}</div>
        ${renderAvatar(store.name || "Store", imageUrl)}
        ${featured ? '<span class="demo-tile__spark">✨</span>' : ""}
        <h3>${escapeHtml(store.name || "Store")}</h3>
        <p>${escapeHtml(location)}</p>
        <div class="demo-meta-row">
          <span class="demo-pill ${open ? "is-open" : "is-closed"}">
            <i class="fas ${open ? "fa-circle-check" : "fa-circle-xmark"}"></i>
            ${open ? "Open" : "Closed"}
          </span>
          ${rating > 0 ? `
            <span class="demo-pill">
              <i class="fas fa-star"></i>
              ${rating.toFixed(1)}
            </span>
          ` : ""}
        </div>
        <div class="demo-score">${footerText}</div>
        <button class="demo-tile__action" data-store-id="${escapeHtml(store.id)}">
          Preview Products
        </button>
      </article>
    `;
  }

  function renderProductTile(product, index) {
    const palette = palettePairs[(index + 1) % palettePairs.length];
    const featured = index === 0;
    const imageUrl = getImageUrl(product.image_url || product.image);
    const badge = String(product.offer_badge || "").trim();
    const hasOffer = badge || product.has_active_offer === true || product.has_active_offer === 1;
    const price = effectivePrice(firstVariant(product) || product);
    const variants = variantLabels(product);
    const previewVariants = variants.slice(0, 3);

    return `
      <article
        class="demo-tile ${featured ? "is-featured" : ""}"
        style="--tile-accent:${palette.accent};--tile-soft:${palette.soft};"
      >
        <div class="demo-rank">${index + 1}</div>
        ${renderAvatar(product.name || "Product", imageUrl)}
        ${featured ? '<span class="demo-tile__spark">🔥</span>' : ""}
        <h3>${escapeHtml(product.name || "Product")}</h3>
        <p>${escapeHtml(productSubtitle(product))}</p>
        ${previewVariants.length ? `
          <div class="demo-variant-stack">
            ${previewVariants
              .map((label) => `<span class="demo-variant-chip">${escapeHtml(label)}</span>`)
              .join("")}
            ${variants.length > previewVariants.length
              ? `<span class="demo-variant-chip">+${variants.length - previewVariants.length} more</span>`
              : ""}
          </div>
        ` : ""}
        <div class="demo-meta-row">
          ${hasOffer ? `
            <span class="demo-pill">
              <i class="fas fa-bolt"></i>
              ${escapeHtml(badge || "Offer")}
            </span>
          ` : ""}
          ${Number(product.stock_quantity) > 0 ? `
            <span class="demo-pill">
              <i class="fas fa-box-open"></i>
              ${escapeHtml(product.stock_quantity)} in stock
            </span>
          ` : `
            <span class="demo-pill is-closed">
              <i class="fas fa-ban"></i>
              Out of stock
            </span>
          `}
        </div>
        <div class="demo-score">PKR ${price.toFixed(0)}</div>
      </article>
    `;
  }

  function renderStores() {
    if (!refs.storeGrid) return;
    refs.storeCountChip.textContent = `${state.filteredStores.length} stores`;
    refs.storeGrid.innerHTML = "";

    if (!state.filteredStores.length) {
      renderEmpty(
        refs.storeGrid,
        "No stores found",
        state.stores.length
          ? "Try a different search term."
          : "There are no stores available right now."
      );
      return;
    }

    refs.storeGrid.innerHTML = state.filteredStores
      .map((store, index) => renderStoreTile(store, index))
      .join("");

    refs.storeGrid.querySelectorAll("[data-store-id]").forEach((button) => {
      button.addEventListener("click", () => {
        const storeId = Number(button.getAttribute("data-store-id"));
        if (!Number.isFinite(storeId)) return;
        loadStoreDetails(storeId);
      });
    });
  }

  function renderSelectedStore() {
    const store = state.selectedStore;
    if (!store) {
      refs.productSection.classList.add("demo-hidden");
      return;
    }

    refs.productSection.classList.remove("demo-hidden");
    refs.productSectionTitle.textContent = `${store.name || "Store"} products`;
    refs.productSectionSubtitle.textContent =
      "Live products loaded from the current database for final testing.";

    const imageUrl = getImageUrl(store.image_url);
    const rating = asNumber(store.rating);
    const delivery = String(store.delivery_time || "").trim();

    refs.selectedStoreSummary.innerHTML = `
      <div class="demo-store-summary__head">
        ${renderAvatar(store.name || "Store", imageUrl)}
        <div class="demo-store-summary__copy">
          <h3>${escapeHtml(store.name || "Store")}</h3>
          <p>${escapeHtml(store.location || "Location not available")}</p>
          ${String(store.status_message || "").trim() ? `<p>${escapeHtml(store.status_message)}</p>` : ""}
          <div class="demo-store-summary__meta">
            <span class="demo-pill ${isOpenStore(store) ? "is-open" : "is-closed"}">
              <i class="fas ${isOpenStore(store) ? "fa-circle-check" : "fa-circle-xmark"}"></i>
              ${isOpenStore(store) ? "Open now" : "Closed"}
            </span>
            ${delivery ? `<span class="demo-pill"><i class="fas fa-clock"></i>${escapeHtml(delivery)} min</span>` : ""}
            ${rating > 0 ? `<span class="demo-pill"><i class="fas fa-star"></i>${rating.toFixed(1)} rating</span>` : ""}
          </div>
        </div>
      </div>
    `;

    refs.productGrid.innerHTML = "";
    if (!state.selectedProducts.length) {
      renderEmpty(
        refs.productGrid,
        "No products available",
        "This store does not have products to preview yet."
      );
      return;
    }

    refs.productGrid.innerHTML = state.selectedProducts
      .map((product, index) => renderProductTile(product, index))
      .join("");
  }

  async function loadStores() {
    renderStatusBanner(refs.storeStatusBanner, "Loading stores...", "info");
    refs.storeCountChip.textContent = "Loading stores...";
    try {
      const response = await fetch(`${API_BASE}/api/stores`);
      const data = await response.json();
      if (!response.ok || !data.success || !Array.isArray(data.stores)) {
        throw new Error(data.message || "Unable to load stores.");
      }
      state.stores = data.stores.slice().sort(compareStores);
      state.filteredStores = state.stores.slice();
      renderStatusBanner(
        refs.storeStatusBanner,
        `${state.filteredStores.length} stores ready for preview`,
        "info"
      );
      renderStores();

      const params = new URLSearchParams(window.location.search);
      const storeId = Number(params.get("store_id"));
      if (Number.isFinite(storeId) && storeId > 0) {
        loadStoreDetails(storeId);
      }
    } catch (error) {
      renderStatusBanner(
        refs.storeStatusBanner,
        error && error.message ? error.message : "Unable to load stores.",
        "error"
      );
      renderEmpty(refs.storeGrid, "Store load failed", "Please try again shortly.");
    }
  }

  async function loadStoreDetails(storeId) {
    renderStatusBanner(refs.productStatusBanner, "Loading products...", "info");
    refs.productSection.classList.remove("demo-hidden");
    refs.productGrid.innerHTML = "";
    refs.selectedStoreSummary.innerHTML = "";

    try {
      const response = await fetch(`${API_BASE}/api/stores/${storeId}`);
      const data = await response.json();
      if (!response.ok || !data.success || !data.store) {
        throw new Error(data.message || "Unable to load store details.");
      }
      state.selectedStore = data.store;
      state.selectedProducts = Array.isArray(data.products) ? data.products : [];
      renderStatusBanner(
        refs.productStatusBanner,
        `${state.selectedProducts.length} products loaded from live data`,
        "info"
      );
      renderSelectedStore();
      refs.productSection.scrollIntoView({ behavior: "smooth", block: "start" });
      const url = new URL(window.location.href);
      url.searchParams.set("store_id", String(storeId));
      window.history.replaceState({}, "", url);
    } catch (error) {
      renderStatusBanner(
        refs.productStatusBanner,
        error && error.message ? error.message : "Unable to load products.",
        "error"
      );
      renderEmpty(refs.productGrid, "Product load failed", "Please try again shortly.");
    }
  }

  function bindEvents() {
    refs.storeSearch.addEventListener("input", (event) => {
      const query = String(event.target.value || "").trim().toLowerCase();
      if (!query) {
        state.filteredStores = state.stores.slice();
      } else {
        state.filteredStores = state.stores.filter((store) => {
          const name = String(store.name || "").toLowerCase();
          const location = String(store.location || "").toLowerCase();
          const category = String(store.category_name || "").toLowerCase();
          return name.includes(query) || location.includes(query) || category.includes(query);
        });
      }
      renderStatusBanner(
        refs.storeStatusBanner,
        `${state.filteredStores.length} stores ready for preview`,
        "info"
      );
      renderStores();
    });

    refs.backToStoresBtn.addEventListener("click", () => {
      state.selectedStore = null;
      state.selectedProducts = [];
      refs.productSection.classList.add("demo-hidden");
      const url = new URL(window.location.href);
      url.searchParams.delete("store_id");
      window.history.replaceState({}, "", url);
      document.querySelector(".demo-section")?.scrollIntoView({
        behavior: "smooth",
        block: "start",
      });
    });
  }

  bindEvents();
  loadStores();
})();
