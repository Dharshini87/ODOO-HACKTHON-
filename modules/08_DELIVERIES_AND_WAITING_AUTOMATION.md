20. DELIVERIES
============================================================

Delivery represents outbound inventory.

Before allowing READY:

free_to_use >= requested quantity

If sufficient:

DRAFT → READY

READY delivery reserves quantity.

Example:

On Hand = 50
Reserved = 0
Free = 50

Delivery = 20

READY:

On Hand = 50
Reserved = 20
Free = 30

DONE:

On Hand = 30
Reserved = 0
Free = 30

If insufficient:

DRAFT → WAITING

Mobile UI MUST clearly show:

On Hand
Reserved
Free to Use
Requested
Shortage

Example:

On Hand = 10
Reserved = 5
Free = 5
Requested = 20
Shortage = 15

Show:

WAITING FOR STOCK

============================================================
21. WAITING → READY
============================================================

Do NOT use Redis, Celery, or a background worker for MVP.

When a receipt or other stock-increasing transaction completes:

1. Increase inventory.
2. Find WAITING deliveries.
3. Process oldest-created-first.
4. Check all products.
5. If ALL products are available:
   - reserve stock
   - change WAITING → READY
6. Otherwise leave WAITING.

No partial fulfillment.

A multi-product delivery becomes READY only when ALL products are available.

============================================================
