24. STOCK LEDGER
============================================================

stock_ledger:

- id
- transaction_id
- product_id
- location_id
- quantity_before
- quantity_change
- quantity_after
- movement_type
- created_at

Movement types:

RECEIPT
DELIVERY
TRANSFER_IN
TRANSFER_OUT
ADJUSTMENT

Ledger is:

READ ONLY
APPEND ONLY
IMMUTABLE

Mobile UI should display ledger as a vertical timeline.

============================================================
25. MOVE HISTORY
============================================================

Do NOT create a separate move history table.

GET:

/api/moves

Derive data from:

transactions
transaction_items
stock_ledger

Mobile display:

Reference
Date
Contact
From
To
Quantity
Status

Search:

Reference
Contact
SKU

Filters:

Type
Status
Product
Warehouse
Location
Date

Support:

List view

Kanban view as secondary/optional.

============================================================
