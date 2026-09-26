"""
Section 49: DEMO DATA
Seed:
WAREHOUSE:
  Main Warehouse (WH)
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
"""
from decimal import Decimal
import datetime
from sqlalchemy.orm import Session

from .database import SessionLocal, engine, Base
from . import models, auth


def seed_demo_data(db: Session) -> dict:
    """
    Seeds all entities mandated by Section 49 DEMO DATA.
    Idempotent and safe to run multiple times.
    """
    Base.metadata.create_all(bind=db.get_bind())

    # 1. WAREHOUSE: Main Warehouse (WH)
    wh = db.query(models.Warehouse).filter(models.Warehouse.short_code == "WH").first()
    if not wh:
        wh = db.query(models.Warehouse).filter(models.Warehouse.name == "Main Warehouse").first()
    if not wh:
        wh = models.Warehouse(
            name="Main Warehouse",
            short_code="WH",
            address="Plot 10, Industrial Logistics Hub",
            is_active=True,
        )
        db.add(wh)
        db.commit()
        db.refresh(wh)
    else:
        wh.name = "Main Warehouse"
        wh.short_code = "WH"
        wh.is_active = True
        db.commit()

    # 2. LOCATIONS: Rack A, Rack B, Production Floor
    location_specs = [
        ("Rack A", "RACK-A", False),
        ("Rack B", "RACK-B", False),
        ("Production Floor", "PROD-FLR", False),
    ]
    locations = {}
    for name, code, is_virt in location_specs:
        loc = db.query(models.Location).filter(
            models.Location.warehouse_id == wh.id,
            models.Location.name == name,
        ).first()
        if not loc:
            loc = models.Location(
                name=name,
                short_code=code,
                warehouse_id=wh.id,
                is_virtual=is_virt,
                is_active=True,
            )
            db.add(loc)
            db.commit()
            db.refresh(loc)
        locations[name] = loc

    # 3. CATEGORIES: Raw Materials, Finished Goods, Components
    category_names = ["Raw Materials", "Finished Goods", "Components"]
    categories = {}
    for cat_name in category_names:
        c = db.query(models.Category).filter(models.Category.name == cat_name).first()
        if not c:
            c = models.Category(name=cat_name)
            db.add(c)
            db.commit()
            db.refresh(c)
        categories[cat_name] = c

    # 4. PRODUCTS: Steel Rod, Chair, Table
    product_specs = [
        ("Steel Rod", "STL-ROD", "Raw Materials", "kg", Decimal("45.00"), Decimal("20.000")),
        ("Chair", "CHR-001", "Finished Goods", "unit", Decimal("120.00"), Decimal("10.000")),
        ("Table", "TBL-001", "Finished Goods", "unit", Decimal("350.00"), Decimal("5.000")),
    ]
    products = {}
    for name, sku, cat_name, uom, cost, reorder in product_specs:
        p = db.query(models.Product).filter(models.Product.name == name).first()
        if not p:
            p = db.query(models.Product).filter(models.Product.sku == sku).first()
        if not p:
            p = models.Product(
                name=name,
                sku=sku,
                category_id=categories[cat_name].id,
                unit_of_measure=uom,
                cost_per_unit=cost,
                reorder_point=reorder,
                is_active=True,
            )
            db.add(p)
            db.commit()
            db.refresh(p)
        products[name] = p

    # 5. USERS: Inventory Manager, Warehouse Staff
    manager = db.query(models.User).filter(models.User.email == "manager@stocksense.com").first()
    if not manager:
        manager = models.User(
            name="Inventory Manager",
            email="manager@stocksense.com",
            password_hash=auth.hash_password("password123"),
            role="INVENTORY_MANAGER",
            is_active=True,
        )
        db.add(manager)
        db.commit()
        db.refresh(manager)

    staff = db.query(models.User).filter(models.User.email == "staff@stocksense.com").first()
    if not staff:
        staff = models.User(
            name="Warehouse Staff",
            email="staff@stocksense.com",
            password_hash=auth.hash_password("password123"),
            role="WAREHOUSE_STAFF",
            is_active=True,
        )
        db.add(staff)
        db.commit()
        db.refresh(staff)

    return {
        "warehouse": wh,
        "locations": locations,
        "categories": categories,
        "products": products,
        "users": {
            "manager": manager,
            "staff": staff,
        },
    }


if __name__ == "__main__":
    db = SessionLocal()
    try:
        data = seed_demo_data(db)
        print("============================================================")
        print("STOCK SENSE - SECTION 49 DEMO DATA SEEDED SUCCESSFULLY")
        print("============================================================")
        print(f"Warehouse: {data['warehouse'].name} ({data['warehouse'].short_code})")
        print(f"Locations: {list(data['locations'].keys())}")
        print(f"Categories: {list(data['categories'].keys())}")
        print(f"Products: {list(data['products'].keys())}")
        print("Users:")
        print("  - Inventory Manager: manager@stocksense.com / password123")
        print("  - Warehouse Staff:   staff@stocksense.com / password123")
        print("============================================================")
    finally:
        db.close()
