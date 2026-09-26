# MODULE 03: 03_DATABASE_AND_DATA_INTEGRITY

============================================================
7. DATABASE
============================================================

Use PostgreSQL.

Use SQLAlchemy and Alembic.

Create:

users
categories
products
warehouses
locations
stock
transactions
transaction_items
stock_ledger
password_reset_tokens
idempotency_keys

============================================================
13. STOCK MODEL
============================================================

stock:

- id
- product_id
- location_id
- on_hand
- reserved
- version
- updated_at

Use:

NUMERIC(12,3)

Constraints:

UNIQUE(product_id, location_id)

on_hand >= 0

reserved >= 0

reserved <= on_hand

CRITICAL:

Do NOT store free_to_use.

Always calculate:

free_to_use = on_hand - reserved

The mobile UI must clearly show:

ON HAND
RESERVED
FREE TO USE

============================================================
14. TRANSACTIONS
============================================================

Use ONE unified transaction model.

transactions:

- id
- reference
- type
- status
- source_location_id
- destination_location_id
- party_name
- contact
- delivery_address
- schedule_date
- reason
- created_by
- validated_by
- created_at
- updated_at
- validated_at
- canceled_at

Types:

RECEIPT
DELIVERY
TRANSFER
ADJUSTMENT

============================================================
15. TRANSACTION ITEMS
============================================================

transaction_items:

- id
- transaction_id
- product_id
- quantity
- adjustment_delta

Normal transactions:

quantity = movement quantity

Adjustment:

quantity = physical count

adjustment_delta =
physical count - current stock

============================================================
16. TRANSACTION STATES
============================================================

Use exactly:

DRAFT
WAITING
READY
DONE
CANCELED

Workflow:

DRAFT
 ├── insufficient stock → WAITING
 └── stock available → READY

WAITING
 └── stock becomes available → READY

READY
 └── validate → DONE

DRAFT → CANCELED
WAITING → CANCELED
READY → CANCELED

DONE is immutable.

Do not allow DONE transactions to be edited or canceled.

============================================================
17. RESERVATION MODEL
============================================================

Do NOT create a reservation table.

Use:

stock.reserved

Rules:

DRAFT:
no stock impact
no reservation

WAITING:
no stock impact
no reservation

READY DELIVERY:
reserve quantity

DONE DELIVERY:
decrease on_hand
release reservation

CANCELED READY DELIVERY:
release reservation
do not change on_hand

Formula:

FREE TO USE = ON HAND - RESERVED

Never allow:

reserved > on_hand

============================================================
42. DATABASE INTEGRITY
============================================================

Use:

Foreign keys
Unique constraints
Check constraints
Indexes
Transactions
Row locking

Critical constraints:

SKU unique

Reference unique

Product/location stock unique

on_hand >= 0

reserved >= 0

reserved <= on_hand

Valid transaction type

Valid transaction state

Valid quantities

Adjustment reason required

Adjustment cannot reduce below reserved

============================================================
43. SOFT DELETION
============================================================

Products, categories, warehouses, and locations should use:

is_active

rather than hard deletion when historical transactions depend on them.

Never delete historical transactions or ledger entries.

============================================================
