49. DEMO DATA
============================================================

Seed:

WAREHOUSE:

Main Warehouse
WH

LOCATIONS:

Rack A
Rack B
Production Floor

CATEGORIES:

Raw Materials
Finished Goods
Components

PRODUCTS:

Steel Rod
Chair
Table

USERS:

Inventory Manager
Warehouse Staff

============================================================
50. REQUIRED DEMO FLOW
============================================================

The application must support this exact demo:

1. Login.

2. Create Steel Rod.

3. Receive 100 kg.

4. Stock becomes:

100 kg

5. Transfer 30 kg:

Main Warehouse → Production Floor

Result:

Main Warehouse = 70 kg
Production Floor = 30 kg

6. Deliver 20 kg.

Total:

80 kg

7. Adjust -3 kg damaged.

Total:

77 kg

8. Open Move History.

9. Open Stock Ledger.

10. Open Inventory Intelligence.

============================================================
51. ADVANCED DEMO
============================================================

Demonstrate:

Available stock = 5

Create delivery:

20

Result:

WAITING

Then receive:

15

System checks waiting deliveries.

Delivery becomes:

READY

System reserves stock.

Validate.

Delivery becomes:

DONE

Stock is correctly reduced.

============================================================
