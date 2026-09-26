22. TRANSFERS
============================================================

Transfers move inventory between locations.

Example:

Main Warehouse / Rack A
        ↓
Production Floor

30 kg

Source:

on_hand -= 30

Destination:

on_hand += 30

Transfer must use FREE TO USE stock only.

Reserved inventory cannot be transferred.

Create:

TRANSFER_OUT ledger entry

and:

TRANSFER_IN ledger entry

Both must occur atomically.

Mobile screens:

Transfer List
Create Transfer
Transfer Detail

============================================================
