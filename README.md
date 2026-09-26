# StockSense

A ledger-based Inventory Management System (IMS) built for the Odoo hackathon.
Every stock change — receipts, deliveries, transfers, adjustments — is an
append-only entry in a single stock ledger, so current stock is always
*derived*, never manually edited. This mirrors how Odoo's own Inventory app
works internally (virtual locations for Vendors/Customers/Inventory
Adjustment as ledger endpoints).

## Stack
- **Backend:** FastAPI + SQLAlchemy + SQLite, JWT auth
- **Frontend:** React + Vite + Tailwind CSS + React Router

## Quick start

### 1. Backend
```bash
cd backend
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Seed demo data (creates a login + sample warehouses/products/stock)
python -m app.seed

# Run the API
python -m uvicorn app.main:app --reload --port 8000
```
API docs (Swagger UI) will be at **http://localhost:8000/docs**.

Demo login: `manager@stocksense.com` / `password123`

### 2. Frontend
```bash
cd frontend
npm install
npm run dev
```
App runs at **http://localhost:5173**.

> The frontend points at `http://localhost:8000` (see `src/api.js`). Change
> `BASE_URL` there if you deploy the backend elsewhere.

## What's implemented

| Feature | Where |
|---|---|
| Signup / Login (JWT) | `/auth/signup`, `/auth/login-json` |
| OTP-based password reset | `/auth/forgot-password`, `/auth/reset-password` — OTP is printed to the backend console (no email/SMS provider wired up for the demo) |
| Products & categories | `/products`, `/categories` |
| Warehouses & locations | `/warehouses`, `/warehouses/locations` |
| Receipts (inbound) | `/receipts` — draft → validate → stock **increases** |
| Delivery orders (outbound) | `/deliveries` — auto-blocked with `"Insufficient stock available"` if balance is too low, flips to `waiting` |
| Internal transfers | `/transfers` — net enterprise stock unchanged, per-location stock updates |
| Stock adjustments | `/adjustments` — reconciles a physical count against the ledger |
| Move History | `/move-history` — full ledger, searchable/filterable by type, status, reference, contact |
| "Last incoming stock" per product | `/move-history/last-incoming/{product_id}` |
| Dashboard KPIs | `/dashboard` — total products, low/out of stock, pending receipts/deliveries, transfers scheduled |

## Demo script for judges (2 minutes)

1. **Log in** with the seeded manager account.
2. **Dashboard** — show the KPI tiles are live (1 product seeded with 500 boxes on hand).
3. **Receipts** — create a new receipt, validate it, watch stock go up.
4. **Delivery** — create a delivery for *more* than what's on hand → show it
   gets blocked with the exact "Insufficient stock available" error and sits
   in `Waiting`. Then create a smaller delivery and validate it → stock drops.
5. **Transfers** — move stock between two locations, validate it, note total
   company-wide stock is unchanged (check the Stock page).
6. **Adjustments** — pick a product/location, enter a "counted" quantity that
   differs from what's recorded, submit → see the diff logged automatically.
7. **Move History** — show the entire ledger trail, filter by type/status,
   point out every action from steps 3–6 is permanently recorded here.

## Project structure
```
stocksense/
├── backend/
│   └── app/
│       ├── main.py            # FastAPI app + router wiring
│       ├── models.py          # SQLAlchemy models (StockMove is the ledger)
│       ├── schemas.py         # Pydantic request/response schemas
│       ├── auth.py            # JWT + password hashing
│       ├── ledger.py          # Core stock-computation logic
│       ├── seed.py            # Demo data seeder
│       └── routers/           # One router per feature area
└── frontend/
    └── src/
        ├── api.js             # API client
        ├── AuthContext.jsx    # Login state
        ├── App.jsx            # Routes
        ├── components/        # Shell, Modal, StatusBadge
        └── pages/              # One page per feature area
```


