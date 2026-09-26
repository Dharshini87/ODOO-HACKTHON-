# MODULE 05: 05_MASTER_DATA

============================================================
9. CATEGORIES
============================================================

categories:

- id
- name
- description
- is_active
- created_at

Category name should be unique.

============================================================
10. PRODUCTS
============================================================

products:

- id
- name
- sku
- category_id
- unit_of_measure
- unit_cost
- reorder_level
- is_active
- created_at
- updated_at

Constraints:

SKU unique.

reorder_level >= 0.

Use NUMERIC for monetary and quantity values.

============================================================
11. WAREHOUSES
============================================================

warehouses:

- id
- name
- short_code
- address
- is_active
- created_at
- updated_at

short_code unique.

============================================================
12. LOCATIONS
============================================================

locations:

- id
- warehouse_id
- name
- short_code
- is_active
- created_at
- updated_at

Each location belongs to one warehouse.

============================================================
