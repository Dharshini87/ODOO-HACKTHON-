# MODULE 06: 06_INVENTORY_ENGINE

============================================================
18. INVENTORY TRANSACTION ENGINE
============================================================

ALL inventory mutations must occur in backend database transactions.

Never perform inventory mutation directly inside Flutter.

Flow:

BEGIN TRANSACTION

1. Lock transaction.
2. Lock affected stock rows.
3. Lock rows in deterministic order.
4. Validate transaction status.
5. Validate products.
6. Validate locations.
7. Validate quantities.
8. Validate available stock.
9. Apply stock changes.
10. Apply reservations.
11. Write ledger entries.
12. Update transaction.
13. COMMIT.

On any failure:

ROLLBACK EVERYTHING.

Support:

- concurrency
- simultaneous deliveries
- simultaneous transfers
- simultaneous adjustments
- simultaneous receipts
- duplicate validation
- stock row creation races
- insufficient stock
- deadlock prevention

Use PostgreSQL SELECT FOR UPDATE where required.

============================================================
40. IDEMPOTENCY
============================================================

Use Idempotency-Key for mutation requests.

Especially:

POST /api/transactions/{id}/validate

Protect against:

- double taps
- network retries
- duplicate requests
- app retry

A transaction must never mutate inventory twice.

Create:

idempotency_keys

with unique:

key + endpoint + user

============================================================
41. REFERENCES
============================================================

Backend generates references.

Examples:

WH/IN/0001
WH/OUT/0001
WH/TR/0001
WH/ADJ/0001

Mappings:

RECEIPT → IN
DELIVERY → OUT
TRANSFER → TR
ADJUSTMENT → ADJ

Use PostgreSQL sequences.

Never use:

MAX(id) + 1

Flutter must never generate references.

============================================================
