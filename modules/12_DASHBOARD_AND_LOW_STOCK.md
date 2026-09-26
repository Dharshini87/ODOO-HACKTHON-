26. DASHBOARD
============================================================

GET:

/api/dashboard/summary

Dashboard must be database-driven.

Display:

Total Stock

Low Stock

Out of Stock

Pending Receipts

Pending Deliveries

Waiting Deliveries

Transfers Scheduled

Also show:

Low Stock Products
Recent Movements
Inventory Intelligence preview

Never hardcode dashboard numbers.

============================================================
27. LOW STOCK
============================================================

Product-level reorder_level.

Rules:

if on_hand == 0:
    OUT OF STOCK

elif on_hand <= reorder_level:
    LOW STOCK

else:
    NORMAL

The UI should display:

On Hand
Reserved
Free to Use

============================================================
