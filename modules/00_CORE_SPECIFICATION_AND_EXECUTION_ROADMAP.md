# MODULE 00: 00_CORE_SPECIFICATION_AND_EXECUTION_ROADMAP

You are the lead Flutter architect and senior full-stack engineer responsible for building a complete production-quality mobile application called STOCKSENSE.

Build the application end-to-end.

IMPORTANT:
This is a MOBILE APPLICATION, not a web application.

The primary client must be a Flutter Android application.

The authoritative architecture is:

Flutter Android App
        ↓ HTTPS REST API
FastAPI Backend
        ↓ SQLAlchemy
PostgreSQL Database

The Flutter application must NEVER connect directly to PostgreSQL.

Treat this prompt as the source of truth for the application architecture and business logic.

Do not replace the architecture with a different framework or simplify away critical inventory logic.

============================================================
1. PRODUCT
============================================================

Application name:

StockSense

Tagline:

Smart Inventory. Clear Decisions.

StockSense is a mobile Inventory Management System for:

1. Warehouse Staff
2. Inventory Managers

The application replaces manual inventory registers, spreadsheets, and fragmented stock tracking with a centralized inventory management system.

The application must support:

- Authentication
- Products
- Categories
- Warehouses
- Locations
- Stock
- Receipts
- Delivery Orders
- Internal Transfers
- Inventory Adjustments
- Move History
- Stock Ledger
- Dashboard
- Low-stock detection
- Inventory Intelligence
- Notifications
- Profile and Settings

The backend is the single source of truth.

Flutter must never directly modify inventory quantities.

============================================================
2. TECHNOLOGY STACK
============================================================

MOBILE:

Flutter
Dart
Material 3
Riverpod
GoRouter
Dio
flutter_secure_storage
JSON serialization

BACKEND:

Python
FastAPI
SQLAlchemy
Alembic
Pydantic
JWT
bcrypt or Argon2

DATABASE:

PostgreSQL

Do NOT introduce:

- React
- React Native
- Firebase as the primary database
- Supabase as the primary database
- GraphQL
- Kafka
- Redis
- Kubernetes
- Microservices
- Event sourcing
- LLM chatbot
- unnecessary background workers

Keep the backend as a modular monolith.

============================================================
46. DEVELOPMENT PHASES
============================================================

IMPLEMENT IN THIS ORDER.

PHASE 1:

Flutter foundation

- project setup
- theme
- navigation
- reusable components
- Riverpod
- GoRouter
- Dio
- secure storage

PHASE 2:

Backend foundation

- FastAPI
- PostgreSQL
- SQLAlchemy
- Alembic
- environment configuration
- health endpoint

PHASE 3:

Database

- models
- relationships
- constraints
- indexes
- migrations
- seed data

PHASE 4:

Authentication

- register
- login
- JWT
- roles
- OTP password reset

PHASE 5:

Master data

- categories
- products
- warehouses
- locations

PHASE 6:

Inventory engine

- stock
- reservation
- locking
- ledger
- transaction state machine
- idempotency

PHASE 7:

Receipts

PHASE 8:

Deliveries

PHASE 9:

Transfers

PHASE 10:

Adjustments

PHASE 11:

Move History
Stock Ledger

PHASE 12:

Dashboard

PHASE 13:

Inventory Intelligence

PHASE 14:

Notifications
Profile
Settings

PHASE 15:

Error/loading/empty states

PHASE 16:

Testing

PHASE 17:

Production deployment

============================================================
