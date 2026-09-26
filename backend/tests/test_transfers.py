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
def transfers_client_and_db():
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


def test_section_22_transfer_lifecycle_and_atomic_ledger_entries(transfers_client_and_db):
    """
    Section 22: TRANSFERS
    Example:
      Main Warehouse / Rack A -> Production Floor (30 kg)
      Source: on_hand -= 30
      Destination: on_hand += 30
      TRANSFER_OUT and TRANSFER_IN ledger entries atomically created.
    """
    client, db, mgr_headers, staff_headers = transfers_client_and_db

    # 1. Setup master data
    cat = models.Category(name="Raw Materials", is_active=True)
    db.add(cat)
    db.flush()

    prod = models.Product(
        name="Steel Rod",
        sku="ST-ROD-01",
        category_id=cat.id,
        unit_of_measure="kg",
        unit_cost=Decimal("15.00"),
        reorder_level=Decimal("50.00"),
        is_active=True,
    )
    db.add(prod)

    wh = models.Warehouse(name="Main Warehouse", short_code="WH", address="10 Industrial", is_active=True)
    db.add(wh)
    db.flush()

    rack_a = models.Location(name="Rack A", short_code="RACK-A", warehouse_id=wh.id, is_active=True)
    prod_floor = models.Location(name="Production Floor", short_code="PROD", warehouse_id=wh.id, is_active=True)
    db.add_all([rack_a, prod_floor])
    db.flush()

    # Initial stock: Rack A has 50 kg, Production Floor has 0
    stock_rack_a = models.Stock(
        product_id=prod.id,
        location_id=rack_a.id,
        on_hand=Decimal("50.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    stock_prod_floor = models.Stock(
        product_id=prod.id,
        location_id=prod_floor.id,
        on_hand=Decimal("0.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add_all([stock_rack_a, stock_prod_floor])
    db.commit()

    # 2. Create Transfer: Rack A -> Production Floor, 30 kg
    create_payload = {
        "from_location_id": rack_a.id,
        "to_location_id": prod_floor.id,
        "product_id": prod.id,
        "quantity": 30.0,
        "contact": "Internal Shift Move",
    }
    resp = client.post("/transfers", json=create_payload, headers=staff_headers)
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["status"] == "draft"
    assert data["reference"].startswith("WH/TR/")
    assert data["quantity"] == 30.0
    transfer_id = data["id"]

    # 3. Mark READY
    ready_resp = client.post(f"/transfers/{transfer_id}/ready", headers=staff_headers)
    assert ready_resp.status_code == 200, ready_resp.text
    assert ready_resp.json()["status"] == "ready"

    # 4. Validate Transfer (Source on_hand -= 30, Destination on_hand += 30)
    val_resp = client.post(f"/transfers/{transfer_id}/validate", headers=staff_headers)
    assert val_resp.status_code == 200, val_resp.text
    val_data = val_resp.json()
    assert val_data["status"] == "done"

    # Verify both ledger entries in response
    assert val_data["transfer_out_ledger"] is not None
    assert val_data["transfer_out_ledger"]["quantity_change"] == -30.0
    assert val_data["transfer_out_ledger"]["movement_type"] == "TRANSFER_OUT"

    assert val_data["transfer_in_ledger"] is not None
    assert val_data["transfer_in_ledger"]["quantity_change"] == 30.0
    assert val_data["transfer_in_ledger"]["movement_type"] == "TRANSFER_IN"

    # Verify DB stock state: Rack A = 20, Production Floor = 30
    db.expire_all()
    st_rack_a = db.query(models.Stock).filter_by(product_id=prod.id, location_id=rack_a.id).first()
    st_prod_floor = db.query(models.Stock).filter_by(product_id=prod.id, location_id=prod_floor.id).first()

    assert st_rack_a.on_hand == Decimal("20.000")
    assert st_prod_floor.on_hand == Decimal("30.000")


def test_section_22_transfer_must_use_free_to_use_stock_only(transfers_client_and_db):
    """
    Section 22:
    "Transfer must use FREE TO USE stock only.
     Reserved inventory cannot be transferred."
    """
    client, db, mgr_headers, staff_headers = transfers_client_and_db

    cat = models.Category(name="Electronics", is_active=True)
    db.add(cat)
    db.flush()

    prod = models.Product(
        name="Sensor Unit",
        sku="SN-01",
        category_id=cat.id,
        unit_of_measure="unit",
        unit_cost=Decimal("50.00"),
        reorder_level=Decimal("10.00"),
        is_active=True,
    )
    db.add(prod)

    wh = models.Warehouse(name="East Hub", short_code="EH", address="East Road", is_active=True)
    db.add(wh)
    db.flush()

    loc1 = models.Location(name="Bay 1", short_code="B1", warehouse_id=wh.id, is_active=True)
    loc2 = models.Location(name="Bay 2", short_code="B2", warehouse_id=wh.id, is_active=True)
    db.add_all([loc1, loc2])
    db.flush()

    # Source has On Hand = 40, Reserved = 20 -> FREE TO USE = 20!
    stock1 = models.Stock(
        product_id=prod.id,
        location_id=loc1.id,
        on_hand=Decimal("40.000"),
        reserved=Decimal("20.000"),
        version=1,
    )
    stock2 = models.Stock(
        product_id=prod.id,
        location_id=loc2.id,
        on_hand=Decimal("0.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add_all([stock1, stock2])
    db.commit()

    # Request transfer of 30 units (30 <= 40 on_hand, but 30 > 20 free_to_use!)
    create_payload = {
        "from_location_id": loc1.id,
        "to_location_id": loc2.id,
        "product_id": prod.id,
        "quantity": 30.0,
    }
    resp = client.post("/transfers", json=create_payload, headers=staff_headers)
    assert resp.status_code == 201
    transfer_id = resp.json()["id"]

    # Attempt to mark READY -> Must fail because free_to_use (20) < requested (30)
    ready_resp = client.post(f"/transfers/{transfer_id}/ready", headers=staff_headers)
    assert ready_resp.status_code == 400
    assert "free to use" in ready_resp.json()["detail"].lower()

    # Attempt to validate -> Must fail because cannot use reserved inventory
    val_resp = client.post(f"/transfers/{transfer_id}/validate", headers=staff_headers)
    assert val_resp.status_code == 400

    # Stock must remain unchanged
    db.expire_all()
    st1 = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc1.id).first()
    st2 = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc2.id).first()
    assert st1.on_hand == Decimal("40.000")
    assert st1.reserved == Decimal("20.000")
    assert st2.on_hand == Decimal("0.000")


def test_transfer_validation_prevents_same_location(transfers_client_and_db):
    """
    Source and destination locations cannot be identical.
    """
    client, db, mgr_headers, staff_headers = transfers_client_and_db

    wh = models.Warehouse(name="Hub", short_code="H", address="Addr", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Bay X", short_code="BX", warehouse_id=wh.id, is_active=True)
    prod = models.Product(name="Item", sku="ITM-1", unit_of_measure="unit", cost_per_unit=Decimal("1.00"), is_active=True)
    db.add_all([loc, prod])
    db.commit()

    resp = client.post(
        "/transfers",
        json={"from_location_id": loc.id, "to_location_id": loc.id, "product_id": prod.id, "quantity": 10.0},
        headers=staff_headers,
    )
    assert resp.status_code == 400
    assert "differ" in resp.json()["detail"].lower()
