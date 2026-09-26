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
def deliveries_client_and_db():
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


def test_delivery_sufficient_stock_full_lifecycle(deliveries_client_and_db):
    """
    Section 20 Deliveries:
    Example from spec:
      On Hand = 50
      Reserved = 0
      Free = 50

      Delivery = 20

      READY:
      On Hand = 50
      Reserved = 20
      Free = 30

      DONE:
      On Hand = 30
      Reserved = 0
      Free = 30
    """
    client, db, mgr_headers, staff_headers = deliveries_client_and_db

    # 1. Setup Master Data
    cat = models.Category(name="Electronics", is_active=True)
    db.add(cat)
    db.flush()

    prod = models.Product(
        name="Laptop Pro",
        sku="LP-PRO-01",
        category_id=cat.id,
        unit_of_measure="unit",
        unit_cost=Decimal("1000.00"),
        reorder_level=Decimal("10.00"),
        is_active=True,
    )
    db.add(prod)

    wh = models.Warehouse(name="Main Hub", short_code="MH", address="123 Road", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Stock Bay", short_code="BAY1", warehouse_id=wh.id, is_active=True)
    db.add(loc)
    db.flush()

    # Initial Stock: On Hand = 50, Reserved = 0, Free = 50
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("50.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # 2. Create Delivery in DRAFT: Requested = 20
    create_payload = {
        "from_location_id": loc.id,
        "product_id": prod.id,
        "quantity": 20.0,
        "contact": "Acme Corp",
    }
    resp = client.post("/deliveries", json=create_payload, headers=staff_headers)
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["status"] == "draft"
    assert data["reference"].startswith("MH/OUT/")
    assert data["requested"] == 20.0
    assert data["on_hand"] == 50.0
    assert data["reserved"] == 0.0
    assert data["free_to_use"] == 50.0
    assert data["shortage"] == 0.0
    delivery_id = data["id"]

    # 3. Mark READY: free_to_use (50) >= requested (20)
    ready_resp = client.post(f"/deliveries/{delivery_id}/ready", headers=staff_headers)
    assert ready_resp.status_code == 200, ready_resp.text
    ready_data = ready_resp.json()
    assert ready_data["status"] == "ready"
    assert ready_data["on_hand"] == 50.0
    assert ready_data["reserved"] == 20.0
    assert ready_data["free_to_use"] == 30.0
    assert ready_data["shortage"] == 0.0

    # Verify directly in DB
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.on_hand == Decimal("50.000")
    assert st.reserved == Decimal("20.000")
    assert st.free_to_use == Decimal("30.000")

    # 4. Validate Delivery (READY -> DONE)
    val_resp = client.post(f"/deliveries/{delivery_id}/validate", headers=staff_headers)
    assert val_resp.status_code == 200, val_resp.text
    val_data = val_resp.json()
    assert val_data["status"] == "done"
    assert val_data["on_hand"] == 30.0
    assert val_data["reserved"] == 0.0
    assert val_data["free_to_use"] == 30.0
    assert val_data["ledger_entry"] is not None
    assert val_data["ledger_entry"]["quantity_change"] == -20.0
    assert val_data["ledger_entry"]["movement_type"] == "DELIVERY"

    # Verify DB post-DONE
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.on_hand == Decimal("30.000")
    assert st.reserved == Decimal("0.000")
    assert st.free_to_use == Decimal("30.000")


def test_delivery_insufficient_stock_draft_to_waiting_and_shortage_calculation(deliveries_client_and_db):
    """
    Section 20 Deliveries:
    Example from spec:
      On Hand = 10
      Reserved = 5
      Free = 5
      Requested = 20
      Shortage = 15

      Show: WAITING FOR STOCK
    """
    client, db, mgr_headers, staff_headers = deliveries_client_and_db

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

    wh = models.Warehouse(name="Steel Yard", short_code="SY", address="Industrial Zone", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Yard Rack A", short_code="YR-A", warehouse_id=wh.id, is_active=True)
    db.add(loc)
    db.flush()

    # Initial state: On Hand = 10, Reserved = 5, Free = 5
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("5.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Create Delivery requesting 20 units
    create_payload = {
        "from_location_id": loc.id,
        "product_id": prod.id,
        "quantity": 20.0,
        "contact": "Heavy Build Ltd",
    }
    resp = client.post("/deliveries", json=create_payload, headers=staff_headers)
    assert resp.status_code == 201
    del_id = resp.json()["id"]

    # Attempt to mark READY -> Insufficient stock (Free 5 < Requested 20) -> WAITING
    ready_resp = client.post(f"/deliveries/{del_id}/ready", headers=staff_headers)
    assert ready_resp.status_code == 200
    data = ready_resp.json()
    assert data["status"] == "waiting"
    assert data["is_waiting_for_stock"] is True
    assert data["on_hand"] == 10.0
    assert data["reserved"] == 5.0
    assert data["free_to_use"] == 5.0
    assert data["requested"] == 20.0
    # Shortage = Requested (20) - Free (5) = 15!
    assert data["shortage"] == 15.0

    # Ensure no reservation occurred
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.reserved == Decimal("5.000")
    assert st.on_hand == Decimal("10.000")

    # Cannot validate while WAITING
    val_resp = client.post(f"/deliveries/{del_id}/validate", headers=staff_headers)
    assert val_resp.status_code == 400
    assert "waiting" in val_resp.json()["detail"].lower()


def test_section_21_waiting_to_ready_automated_flow_on_receipt_completion(deliveries_client_and_db):
    """
    Section 21: WAITING -> READY
    When a receipt or other stock-increasing transaction completes:
    1. Increase inventory.
    2. Find WAITING deliveries.
    3. Process oldest-created-first.
    4. Check all products.
    5. If ALL products are available:
       - reserve stock
       - change WAITING -> READY
    6. Otherwise leave WAITING.
    """
    client, db, mgr_headers, staff_headers = deliveries_client_and_db

    cat = models.Category(name="Components", is_active=True)
    db.add(cat)
    db.flush()

    prod = models.Product(
        name="Microcontroller IC",
        sku="MCU-32",
        category_id=cat.id,
        unit_of_measure="unit",
        unit_cost=Decimal("5.00"),
        reorder_level=Decimal("20.00"),
        is_active=True,
    )
    db.add(prod)

    wh = models.Warehouse(name="North Warehouse", short_code="NW", address="45 North", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Bin 1", short_code="B1", warehouse_id=wh.id, is_active=True)
    db.add(loc)
    db.flush()

    # Initial Stock: 0 on hand
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("0.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # 1. Create two deliveries:
    # Delivery 1: requested 15 units (created first)
    # Delivery 2: requested 10 units (created second)
    del1_resp = client.post(
        "/deliveries",
        json={"from_location_id": loc.id, "product_id": prod.id, "quantity": 15.0, "contact": "Client Alpha"},
        headers=staff_headers,
    )
    del1_id = del1_resp.json()["id"]

    del2_resp = client.post(
        "/deliveries",
        json={"from_location_id": loc.id, "product_id": prod.id, "quantity": 10.0, "contact": "Client Beta"},
        headers=staff_headers,
    )
    del2_id = del2_resp.json()["id"]

    # Mark both ready -> both become WAITING
    client.post(f"/deliveries/{del1_id}/ready", headers=staff_headers)
    client.post(f"/deliveries/{del2_id}/ready", headers=staff_headers)

    d1 = client.get(f"/deliveries/{del1_id}", headers=staff_headers).json()
    d2 = client.get(f"/deliveries/{del2_id}", headers=staff_headers).json()
    assert d1["status"] == "waiting"
    assert d2["status"] == "waiting"

    # 2. Receipt arrives for 20 units (enough for Delivery 1 which needs 15, but not for both 15 + 10 = 25)
    rec_resp = client.post(
        "/receipts",
        json={"to_location_id": loc.id, "product_id": prod.id, "quantity": 20.0, "contact": "Micro Supplier"},
        headers=staff_headers,
    )
    rec_id = rec_resp.json()["id"]

    # Validate Receipt: executes 13-step transaction engine and triggers check_waiting_deliveries()!
    val_rec = client.post(f"/receipts/{rec_id}/validate", headers=staff_headers)
    assert val_rec.status_code == 200

    # 3. Check Delivery 1 and Delivery 2 statuses:
    # Oldest-first: Delivery 1 (15 units) got reserved and transitioned WAITING -> READY!
    # Delivery 2 (10 units) needed 10, but remaining free was only 20 - 15 = 5, so it left in WAITING!
    db.expire_all()
    d1_after = client.get(f"/deliveries/{del1_id}", headers=staff_headers).json()
    d2_after = client.get(f"/deliveries/{del2_id}", headers=staff_headers).json()

    assert d1_after["status"] == "ready"
    assert d1_after["reserved"] == 15.0
    assert d1_after["free_to_use"] == 5.0  # 20 on hand - 15 reserved = 5

    assert d2_after["status"] == "waiting"
    assert d2_after["is_waiting_for_stock"] is True
    assert d2_after["shortage"] == 5.0  # Needs 10, free is 5 -> shortage 5!

    # 4. Now a second receipt arrives for 10 units!
    rec2_resp = client.post(
        "/receipts",
        json={"to_location_id": loc.id, "product_id": prod.id, "quantity": 10.0, "contact": "Micro Supplier"},
        headers=staff_headers,
    )
    rec2_id = rec2_resp.json()["id"]
    client.post(f"/receipts/{rec2_id}/validate", headers=staff_headers)

    # Now Delivery 2 should automatically become READY!
    db.expire_all()
    d2_final = client.get(f"/deliveries/{del2_id}", headers=staff_headers).json()
    assert d2_final["status"] == "ready"
    assert d2_final["reserved"] == 25.0  # 15 for D1 + 10 for D2
    assert d2_final["free_to_use"] == 5.0  # 30 on hand - 25 reserved = 5


def test_section_6_and_16_delivery_cancellation_rbac(deliveries_client_and_db):
    """
    Section 6 & 16:
    Cancel Transaction permissions:
      STAFF: NO (403 Forbidden)
      MANAGER: YES
    When a READY delivery is canceled, its reservations are released and check_waiting_deliveries() runs!
    """
    client, db, mgr_headers, staff_headers = deliveries_client_and_db

    cat = models.Category(name="Tools", is_active=True)
    db.add(cat)
    db.flush()

    prod = models.Product(
        name="Wrench Set",
        sku="WR-01",
        category_id=cat.id,
        unit_of_measure="set",
        unit_cost=Decimal("25.00"),
        reorder_level=Decimal("5.00"),
        is_active=True,
    )
    db.add(prod)

    wh = models.Warehouse(name="West Hub", short_code="WH", address="West Street", is_active=True)
    db.add(wh)
    db.flush()

    loc = models.Location(name="Bay W", short_code="BW", warehouse_id=wh.id, is_active=True)
    db.add(loc)
    db.flush()

    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Create delivery by Manager for 10 units & mark READY
    resp = client.post(
        "/deliveries",
        json={"from_location_id": loc.id, "product_id": prod.id, "quantity": 10.0, "contact": "Auto Repair"},
        headers=mgr_headers,
    )
    del_id = resp.json()["id"]
    client.post(f"/deliveries/{del_id}/ready", headers=mgr_headers)

    # Reserved = 10, Free = 0
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.reserved == Decimal("10.000")

    # Staff tries to cancel -> 403 Forbidden
    staff_cancel = client.post(f"/deliveries/{del_id}/cancel", headers=staff_headers)
    assert staff_cancel.status_code == 403

    # Manager cancels -> 200 OK
    mgr_cancel = client.post(f"/deliveries/{del_id}/cancel", headers=mgr_headers)
    assert mgr_cancel.status_code == 200
    assert mgr_cancel.json()["status"] == "canceled"

    # Reservation must be released: on_hand = 10, reserved = 0, free = 10!
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc.id).first()
    assert st.on_hand == Decimal("10.000")
    assert st.reserved == Decimal("0.000")
    assert st.free_to_use == Decimal("10.000")
