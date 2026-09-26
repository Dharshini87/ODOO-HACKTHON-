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
from app.models.transaction import TransactionType, TransactionStatus


@pytest.fixture(scope="function")
def adjustments_client_and_db():
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

    manager = models.User(
        name="Manager User",
        email="manager@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    staff = models.User(
        name="Staff User",
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
    mgr_headers = {"Authorization": f"Bearer {manager_token}"}
    staff_headers = {"Authorization": f"Bearer {staff_token}"}

    yield client, db, mgr_headers, staff_headers

    app.dependency_overrides.clear()
    db.close()


def test_section_23_adjustment_example_from_spec_and_reconciliation(adjustments_client_and_db):
    """
    Section 23:
    System: 80 kg
    Physical: 77 kg
    Adjustment: -3 kg
    Reason: Damaged
    Warehouse Staff can create.
    Inventory Manager validates.
    """
    client, db, mgr_headers, staff_headers = adjustments_client_and_db

    # 1. Setup master data
    cat = models.Category(name="Raw Materials", is_active=True)
    db.add(cat)
    db.flush()

    prod = models.Product(
        name="Steel Rod",
        sku="ST-ROD-80",
        category_id=cat.id,
        unit_of_measure="kg",
        unit_cost=Decimal("15.00"),
        reorder_level=Decimal("50.00"),
        is_active=True,
    )
    db.add(prod)

    wh = models.Warehouse(name="Central Warehouse", short_code="CW", address="100 Main", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Bay 1", short_code="B1", warehouse_id=wh.id, is_active=True)
    db.add(loc)
    db.flush()

    # System stock: 80 kg on hand
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("80.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # 2. Staff creates adjustment: Physical count = 77 kg, Reason = Damaged
    create_payload = {
        "location_id": loc.id,
        "product_id": prod.id,
        "physical_count": 77.0,
        "reason": "Damaged",
    }
    resp = client.post("/adjustments", json=create_payload, headers=staff_headers)
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["status"] == "draft"
    assert data["reference"].startswith("CW/ADJ/")
    assert data["system_quantity"] == 80.0
    assert data["physical_count"] == 77.0
    assert data["difference"] == -3.0
    assert data["reason"] == "Damaged"
    adj_id = data["id"]

    # 3. Staff attempts to validate -> 403 Forbidden (Inventory Manager validates)
    staff_val = client.post(f"/adjustments/{adj_id}/validate", headers=staff_headers)
    assert staff_val.status_code == 403
    assert "manager" in staff_val.json()["detail"].lower()

    # 4. Inventory Manager validates -> 200 OK
    mgr_val = client.post(f"/adjustments/{adj_id}/validate", headers=mgr_headers)
    assert mgr_val.status_code == 200, mgr_val.text
    val_data = mgr_val.json()
    assert val_data["status"] == "done"
    assert val_data["physical_count"] == 77.0
    assert val_data["difference"] == -3.0

    # Verify ledger entry
    assert val_data["ledger_entry"] is not None
    assert val_data["ledger_entry"]["quantity_before"] == 80.0
    assert val_data["ledger_entry"]["quantity_change"] == -3.0
    assert val_data["ledger_entry"]["quantity_after"] == 77.0
    assert val_data["ledger_entry"]["movement_type"] == "ADJUSTMENT"

    # Verify directly in DB
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.on_hand == Decimal("77.000")


def test_section_23_rule_adjustment_cannot_result_in_on_hand_less_than_reserved(adjustments_client_and_db):
    """
    Section 23 Rule:
    Adjustment cannot result in: on_hand < reserved
    """
    client, db, mgr_headers, staff_headers = adjustments_client_and_db

    wh = models.Warehouse(name="Warehouse A", short_code="WA", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Bay A", short_code="BA", warehouse_id=wh.id, is_active=True)
    prod = models.Product(name="Item", sku="ITM-A", unit_of_measure="unit", cost_per_unit=Decimal("10.00"), is_active=True)
    db.add_all([loc, prod])
    db.flush()

    # Initial stock: On Hand = 50, Reserved = 30
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("50.000"),
        reserved=Decimal("30.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Count entered: 20 units (which is < reserved 30!)
    create_payload = {
        "location_id": loc.id,
        "product_id": prod.id,
        "physical_count": 20.0,
        "reason": "Lost",
    }
    resp = client.post("/adjustments", json=create_payload, headers=staff_headers)
    assert resp.status_code == 201
    adj_id = resp.json()["id"]

    # Manager attempts to validate -> Must fail because physical_count (20) < reserved (30)
    val_resp = client.post(f"/adjustments/{adj_id}/validate", headers=mgr_headers)
    assert val_resp.status_code == 400
    assert "reserved" in val_resp.json()["detail"].lower()

    # Stock must remain unchanged
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.on_hand == Decimal("50.000")
    assert st.reserved == Decimal("30.000")


def test_positive_adjustment_found_stock_reconciliation(adjustments_client_and_db):
    """
    Physical count > System quantity (e.g. Found Stock, +5 units).
    """
    client, db, mgr_headers, staff_headers = adjustments_client_and_db

    wh = models.Warehouse(name="Warehouse B", short_code="WB", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Bay B", short_code="BB", warehouse_id=wh.id, is_active=True)
    prod = models.Product(name="Gadget", sku="GDG-01", unit_of_measure="unit", cost_per_unit=Decimal("15.00"), is_active=True)
    db.add_all([loc, prod])
    db.flush()

    # System stock: 10 units
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Count entered: 15 units (Difference = +5)
    create_payload = {
        "location_id": loc.id,
        "product_id": prod.id,
        "physical_count": 15.0,
        "reason": "Found Stock",
    }
    resp = client.post("/adjustments", json=create_payload, headers=staff_headers)
    assert resp.status_code == 201
    adj_id = resp.json()["id"]
    assert resp.json()["difference"] == 5.0

    # Validate
    val_resp = client.post(f"/adjustments/{adj_id}/validate", headers=mgr_headers)
    assert val_resp.status_code == 200
    assert val_resp.json()["status"] == "done"
    assert val_resp.json()["ledger_entry"]["quantity_change"] == 5.0

    # Check stock
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.on_hand == Decimal("15.000")
