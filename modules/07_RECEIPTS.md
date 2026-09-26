# MODULE 07: 07_RECEIPTS

============================================================
19. RECEIPTS
============================================================

Receipt represents incoming stock.

Example:

Receive 100 kg Steel Rod.

When validated:

on_hand += 100

Create ledger:

quantity_before = previous stock
quantity_change = +100
quantity_after = new stock
movement_type = RECEIPT

Receipt flow:

DRAFT → READY → DONE

Mobile screens:

Receipts List
Create Receipt
Receipt Detail
Receipt Detail — Draft
Receipt Detail — Ready
Receipt Detail — Done

============================================================
