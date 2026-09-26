const BASE_URL = "http://localhost:8000";

function getToken() {
  return localStorage.getItem("stocksense_token");
}

async function request(path, { method = "GET", body, auth = true } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (auth) {
    const token = getToken();
    if (token) headers["Authorization"] = `Bearer ${token}`;
  }

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  let data = null;
  try {
    data = await res.json();
  } catch (e) {
    data = null;
  }

  if (!res.ok) {
    const message = data?.detail || `Request failed (${res.status})`;
    const err = new Error(typeof message === "string" ? message : JSON.stringify(message));
    err.status = res.status;
    throw err;
  }

  return data;
}

export const api = {
  // --- Auth ---
  signup: (payload) => request("/auth/signup", { method: "POST", body: payload, auth: false }),
  login: (payload) => request("/auth/login-json", { method: "POST", body: payload, auth: false }),
  forgotPassword: (email) => request("/auth/forgot-password", { method: "POST", body: { email }, auth: false }),
  resetPassword: (payload) => request("/auth/reset-password", { method: "POST", body: payload, auth: false }),

  // --- Dashboard ---
  getDashboard: () => request("/dashboard"),

  // --- Products ---
  getProducts: () => request("/products"),
  createProduct: (payload) => request("/products", { method: "POST", body: payload }),
  updateProduct: (id, payload) => request(`/products/${id}`, { method: "PUT", body: payload }),
  deleteProduct: (id) => request(`/products/${id}`, { method: "DELETE" }),
  getCategories: () => request("/categories"),
  createCategory: (name) => request("/categories", { method: "POST", body: { name } }),

  // --- Warehouses / Locations ---
  getWarehouses: () => request("/warehouses"),
  createWarehouse: (payload) => request("/warehouses", { method: "POST", body: payload }),
  getLocations: () => request("/warehouses/locations"),
  createLocation: (payload) => request("/warehouses/locations", { method: "POST", body: payload }),

  // --- Stock ---
  getStock: (locationId) => request(`/stock${locationId ? `?location_id=${locationId}` : ""}`),

  // --- Receipts ---
  getReceipts: () => request("/receipts"),
  createReceipt: (payload) => request("/receipts", { method: "POST", body: payload }),
  validateReceipt: (id) => request(`/receipts/${id}/validate`, { method: "POST" }),
  cancelReceipt: (id) => request(`/receipts/${id}/cancel`, { method: "POST" }),

  // --- Deliveries ---
  getDeliveries: () => request("/deliveries"),
  createDelivery: (payload) => request("/deliveries", { method: "POST", body: payload }),
  validateDelivery: (id) => request(`/deliveries/${id}/validate`, { method: "POST" }),
  cancelDelivery: (id) => request(`/deliveries/${id}/cancel`, { method: "POST" }),

  // --- Transfers ---
  getTransfers: () => request("/transfers"),
  createTransfer: (payload) => request("/transfers", { method: "POST", body: payload }),
  validateTransfer: (id) => request(`/transfers/${id}/validate`, { method: "POST" }),
  cancelTransfer: (id) => request(`/transfers/${id}/cancel`, { method: "POST" }),

  // --- Adjustments ---
  getAdjustments: () => request("/adjustments"),
  createAdjustment: (payload) => request("/adjustments", { method: "POST", body: payload }),

  // --- Move History ---
  getMoveHistory: (params = {}) => {
    const qs = new URLSearchParams(params).toString();
    return request(`/move-history${qs ? `?${qs}` : ""}`);
  },
  getLastIncoming: (productId, locationId) =>
    request(`/move-history/last-incoming/${productId}${locationId ? `?location_id=${locationId}` : ""}`),
};

export { getToken };
