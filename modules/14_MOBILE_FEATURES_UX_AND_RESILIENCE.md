29. MOBILE SCREENS
============================================================

Implement these screens.

AUTH:

Login
Register
Forgot Password
OTP Verification
Reset Password

HOME:

Dashboard

OPERATIONS:

Operations Home
Receipts List
Create Receipt
Receipt Detail

Delivery List
Create Delivery
Delivery Detail

Transfer List
Create Transfer
Transfer Detail

Adjustment List
Create Adjustment
Adjustment Detail

STOCK:

Stock
Stock Detail
Products
Create Product
Product Detail

HISTORY:

Move History
Move History Filters
Move History Kanban
Stock Ledger

INTELLIGENCE:

Inventory Intelligence
Stockout Risk
Reorder Recommendation
Usage Trend

WAREHOUSE:

Warehouses
Create Warehouse
Warehouse Detail
Locations
Create Location

ACCOUNT:

Notifications
Notification Detail
Profile
Settings
Global Search

SYSTEM:

Loading States
Empty States
Error States
Insufficient Stock State
Confirmation Dialogs
Success Snackbars

============================================================
31. STOCK MOBILE UI
============================================================

Every stock card must make this visible:

Steel Rod
SR-001

Main Warehouse
Rack A

On Hand:
100 kg

Reserved:
20 kg

Free to Use:
80 kg

NORMAL

The relationship must be visually obvious:

ON HAND
-
RESERVED
=
FREE TO USE

============================================================
32. DELIVERY MOBILE UI
============================================================

For available stock:

Steel Rod

Requested:
20 kg

Free to Use:
80 kg

✓ Available

READY

For insufficient stock:

Steel Rod

Requested:
20 kg

Free to Use:
5 kg

Shortage:
15 kg

⚠ Insufficient Available Stock

WAITING

When stock becomes available:

✓ Stock Available

READY

After validation:

DONE

============================================================
33. MOBILE STATUS COLORS
============================================================

Transaction:

DRAFT:
Gray

WAITING:
Amber

READY:
Teal/Blue

DONE:
Green

CANCELED:
Gray/Red

Inventory:

NORMAL:
Green

LOW STOCK:
Amber

OUT OF STOCK:
Red

Never rely on color alone.

Always show text.

============================================================
34. SEARCH AND FILTERING
============================================================

Search products by:

Name
SKU

Search transactions by:

Reference
Contact

Filters:

Type
Status
Warehouse
Location
Category
Product
Date

Use backend filtering for large datasets.

Implement pagination.

============================================================
35. ERROR HANDLING
============================================================

Implement:

Loading state
Empty state
Error state
Retry

Handle:

401 Unauthorized
403 Forbidden
404 Not Found
409 Conflict
422 Validation Error
500 Server Error

Show user-friendly messages.

Never expose raw database exceptions.

============================================================
36. OFFLINE BEHAVIOR
============================================================

MVP should support online-first operation.

Read-only caching may be added.

DO NOT support offline inventory mutations.

If network is unavailable while attempting an inventory operation:

show:

“No Internet Connection”

“Inventory changes require a connection.”

Retry

Never pretend an inventory transaction succeeded while offline.

============================================================
