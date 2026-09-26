import pytest
from decimal import Decimal
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.db.base import Base
from app.database import get_db
from app import models
from app.core import security


@pytest.fixture(scope="function")
def client_and_db():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db

    client = TestClient(app)
    db = TestingSessionLocal()

    # Create manager and staff users
    manager = models.User(
        name="Inventory Manager",
        email="manager@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    staff = models.User(
        name="Warehouse Staff",
        email="staff@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="WAREHOUSE_STAFF",
        is_active=True,
    )
    db.add_all([manager, staff])
    db.commit()

    manager_token = security.create_access_token(
        {"sub": manager.email, "role": manager.role, "user_id": manager.id}
    )
    staff_token = security.create_access_token(
        {"sub": staff.email, "role": staff.role, "user_id": staff.id}
    )

    yield client, db, manager_token, staff_token

    db.close()
    Base.metadata.drop_all(bind=engine)
    app.dependency_overrides.clear()


# ============================================================
# 9. CATEGORIES TESTS
# ============================================================

def test_category_crud_and_uniqueness(client_and_db):
    """Section 9: Category model, unique name constraint, and Section 43 soft deletion."""
    client, db, mgr_tok, staff_tok = client_and_db
    mgr_headers = {"Authorization": f"Bearer {mgr_tok}"}
    staff_headers = {"Authorization": f"Bearer {staff_tok}"}

    # 1. Staff CANNOT create category (Section 6 RBAC: Manage Categories - STAFF: NO)
    staff_res = client.post("/categories", json={"name": "Beverages"}, headers=staff_headers)
    assert staff_res.status_code == 403

    # 2. Manager CAN create category (Section 6 RBAC: Manage Categories - MANAGER: YES)
    cat_payload = {"name": "Beverages", "description": "Hot and cold packaged drinks"}
    create_res = client.post("/categories", json=cat_payload, headers=mgr_headers)
    assert create_res.status_code == 201
    cat_data = create_res.json()
    assert cat_data["name"] == "Beverages"
    assert cat_data["description"] == "Hot and cold packaged drinks"
    assert cat_data["is_active"] is True
    cat_id = cat_data["id"]

    # 3. Duplicate category name must fail (Section 9: Category name should be unique)
    dup_res = client.post("/categories", json={"name": "Beverages"}, headers=mgr_headers)
    assert dup_res.status_code == 400
    assert "already exists" in dup_res.json()["detail"]

    # 4. View categories - Staff CAN view (Section 6 RBAC: View Products - STAFF: YES)
    list_res = client.get("/categories", headers=staff_headers)
    assert list_res.status_code == 200
    assert len(list_res.json()) == 1

    # 5. Soft deletion (Section 43)
    del_res = client.delete(f"/categories/{cat_id}", headers=mgr_headers)
    assert del_res.status_code == 200

    # Verify soft-deleted from active list
    list_active = client.get("/categories", headers=staff_headers).json()
    assert len(list_active) == 0

    # Verify still in database with is_active = False
    raw_cat = db.query(models.Category).filter_by(id=cat_id).first()
    assert raw_cat is not None
    assert raw_cat.is_active is False


# ============================================================
# 10. PRODUCTS TESTS
# ============================================================

def test_product_crud_and_constraints(client_and_db):
    """Section 10: Product model, SKU unique, reorder_level >= 0, NUMERIC values."""
    client, db, mgr_tok, staff_tok = client_and_db
    mgr_headers = {"Authorization": f"Bearer {mgr_tok}"}
    staff_headers = {"Authorization": f"Bearer {staff_tok}"}

    # Create category first
    cat_res = client.post("/categories", json={"name": "Snacks"}, headers=mgr_headers)
    cat_id = cat_res.json()["id"]

    # 1. Staff CANNOT create product (Section 6 RBAC: Manage Products - STAFF: NO)
    staff_create = client.post(
        "/products",
        json={"name": "Potato Chips", "sku": "SNK-001", "category_id": cat_id},
        headers=staff_headers,
    )
    assert staff_create.status_code == 403

    # 2. Manager creates product with valid fields & NUMERIC values
    prod_payload = {
        "name": "Potato Chips",
        "sku": "SNK-001",
        "category_id": cat_id,
        "unit_of_measure": "bag",
        "unit_cost": 25.50,
        "reorder_level": 50.0,
    }
    create_res = client.post("/products", json=prod_payload, headers=mgr_headers)
    assert create_res.status_code == 201
    prod_data = create_res.json()
    assert prod_data["name"] == "Potato Chips"
    assert prod_data["sku"] == "SNK-001"
    assert prod_data["unit_cost"] == 25.50
    assert prod_data["cost_per_unit"] == 25.50  # Synonym compatibility
    assert prod_data["reorder_level"] == 50.0
    prod_id = prod_data["id"]

    # 3. Constraint: SKU unique (Section 10)
    dup_sku = client.post(
        "/products",
        json={
            "name": "Another Chips",
            "sku": "SNK-001",
            "category_id": cat_id,
            "unit_cost": 30.0,
            "reorder_level": 20.0,
        },
        headers=mgr_headers,
    )
    assert dup_sku.status_code == 400
    assert "already exists" in dup_sku.json()["detail"]

    # 4. Constraint: reorder_level >= 0 (Section 10)
    neg_reorder = client.post(
        "/products",
        json={
            "name": "Invalid Reorder Product",
            "sku": "SNK-NEG",
            "category_id": cat_id,
            "unit_cost": 10.0,
            "reorder_level": -5.0,
        },
        headers=mgr_headers,
    )
    assert neg_reorder.status_code == 400
    assert "reorder_level must be >= 0" in neg_reorder.json()["detail"]

    # 5. Staff CAN view products (Section 6 RBAC: View Products - STAFF: YES)
    view_res = client.get("/products", headers=staff_headers)
    assert view_res.status_code == 200
    assert len(view_res.json()) == 1

    # 6. Soft deletion (Section 43)
    del_res = client.delete(f"/products/{prod_id}", headers=mgr_headers)
    assert del_res.status_code == 200
    raw_prod = db.query(models.Product).filter_by(id=prod_id).first()
    assert raw_prod is not None
    assert raw_prod.is_active is False


# ============================================================
# 11. WAREHOUSES TESTS
# ============================================================

def test_warehouse_crud_and_uniqueness(client_and_db):
    """Section 11: Warehouse model, short_code unique, Section 43 soft deletion."""
    client, db, mgr_tok, staff_tok = client_and_db
    mgr_headers = {"Authorization": f"Bearer {mgr_tok}"}
    staff_headers = {"Authorization": f"Bearer {staff_tok}"}

    # 1. Staff CANNOT create warehouse (Section 6 RBAC: Manage Warehouses - STAFF: NO)
    staff_create = client.post(
        "/warehouses",
        json={"name": "Central Hub", "short_code": "WH-CENTRAL", "address": "123 Main St"},
        headers=staff_headers,
    )
    assert staff_create.status_code == 403

    # 2. Manager creates warehouse
    wh_payload = {
        "name": "Central Distribution Center",
        "short_code": "WH-CDC",
        "address": "456 Logistic Ave, Sector 4",
    }
    create_res = client.post("/warehouses", json=wh_payload, headers=mgr_headers)
    assert create_res.status_code == 201
    wh_data = create_res.json()
    assert wh_data["name"] == "Central Distribution Center"
    assert wh_data["short_code"] == "WH-CDC"
    assert wh_data["is_active"] is True
    wh_id = wh_data["id"]

    # 3. Constraint: short_code unique (Section 11)
    dup_wh = client.post(
        "/warehouses",
        json={"name": "Duplicate Code WH", "short_code": "WH-CDC"},
        headers=mgr_headers,
    )
    assert dup_wh.status_code == 400
    assert "already exists" in dup_wh.json()["detail"]

    # 4. Staff CAN view warehouses (Section 6 RBAC)
    view_wh = client.get("/warehouses", headers=staff_headers)
    assert view_wh.status_code == 200
    assert len(view_wh.json()) == 1

    # 5. Soft deletion (Section 43)
    del_wh = client.delete(f"/warehouses/{wh_id}", headers=mgr_headers)
    assert del_wh.status_code == 200
    raw_wh = db.query(models.Warehouse).filter_by(id=wh_id).first()
    assert raw_wh is not None
    assert raw_wh.is_active is False


# ============================================================
# 12. LOCATIONS TESTS
# ============================================================

def test_location_crud_and_warehouse_link(client_and_db):
    """Section 12: Location model, warehouse link, Section 43 soft deletion."""
    client, db, mgr_tok, staff_tok = client_and_db
    mgr_headers = {"Authorization": f"Bearer {mgr_tok}"}
    staff_headers = {"Authorization": f"Bearer {staff_tok}"}

    # Create warehouse first
    wh_res = client.post(
        "/warehouses",
        json={"name": "North Warehouse", "short_code": "WH-NORTH"},
        headers=mgr_headers,
    )
    wh_id = wh_res.json()["id"]

    # 1. Staff CANNOT create location (Section 6 RBAC: Manage Locations - STAFF: NO)
    staff_create = client.post(
        "/warehouses/locations",
        json={"name": "Zone A", "short_code": "LOC-ZA", "warehouse_id": wh_id},
        headers=staff_headers,
    )
    assert staff_create.status_code == 403

    # 2. Location requires valid warehouse (Section 12: Each location belongs to one warehouse)
    invalid_wh = client.post(
        "/warehouses/locations",
        json={"name": "Orphan Zone", "short_code": "LOC-ORPH", "warehouse_id": 99999},
        headers=mgr_headers,
    )
    assert invalid_wh.status_code == 400
    assert "does not exist" in invalid_wh.json()["detail"]

    # 3. Manager creates location
    loc_payload = {
        "name": "Zone A - Bin 1",
        "short_code": "LOC-ZA-B1",
        "warehouse_id": wh_id,
    }
    create_loc = client.post("/warehouses/locations", json=loc_payload, headers=mgr_headers)
    assert create_loc.status_code == 201
    loc_data = create_loc.json()
    assert loc_data["name"] == "Zone A - Bin 1"
    assert loc_data["short_code"] == "LOC-ZA-B1"
    assert loc_data["warehouse_id"] == wh_id
    loc_id = loc_data["id"]

    # 4. Duplicate short_code in same warehouse rejected
    dup_loc = client.post("/warehouses/locations", json=loc_payload, headers=mgr_headers)
    assert dup_loc.status_code == 400

    # 5. Staff CAN view locations
    staff_view = client.get(f"/warehouses/locations?warehouse_id={wh_id}", headers=staff_headers)
    assert staff_view.status_code == 200
    assert len(staff_view.json()) == 1

    # 6. Soft deletion (Section 43)
    del_loc = client.delete(f"/locations/{loc_id}", headers=mgr_headers)
    assert del_loc.status_code == 200
    raw_loc = db.query(models.Location).filter_by(id=loc_id).first()
    assert raw_loc is not None
    assert raw_loc.is_active is False
