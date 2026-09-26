47. TESTING REQUIREMENTS
============================================================

Backend tests must cover:

Authentication
Authorization
Duplicate SKU
Receipt
Delivery
Waiting delivery
Ready delivery
Reservation
Transfer
Adjustment
Ledger
Idempotency
Concurrency
Dashboard
Intelligence

Flutter tests should cover:

Navigation
Authentication state
Forms
Provider states
API success
API failure
Loading
Empty states
Role-specific UI

============================================================
48. CRITICAL CONCURRENCY TEST
============================================================

Test:

Stock = 10

User A tries to deliver 8.

User B simultaneously tries to deliver 8.

The system MUST NOT allow:

negative stock
overselling
invalid reservations
duplicate ledger entries

Use database locking and transactions.

============================================================
