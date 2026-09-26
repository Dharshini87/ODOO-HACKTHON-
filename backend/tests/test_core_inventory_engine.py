import concurrent.futures
from decimal import Decimal
import pytest
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
from app.services.inventory_engine import InventoryTransactionEngine


@pytest.fixture(scope="function")
def engine_test_env():
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
    mgr_headers = {"Authorization": f"Bearer {manager_token}"}
    staff_headers = {"Authorization": f"Bearer {staff_token}"}

    wh = models.Warehouse(name="Main Warehouse", short_code="WH", is_active=True)
    db.add(wh)
    db.commit()

    loc_main = models.Location(warehouse_id=wh.id, name="Main Shelf", short_code="MAIN-01", is_active=True)
    loc_floor = models.Location(warehouse_id=wh.id, name="Production Floor", short_code="PROD-01", is_active=True)
    prod_steel = models.Product(
        name="Steel Rod",
        sku="ST-ROD-ENG",
        unit_of_measure="kg",
        cost_per_unit=Decimal("20.00"),
        reorder_point=Decimal("50.000"),
        is_active=True,
    )
    prod_bolt = models.Product(
        name="Industrial Bolt",
        sku="BOLT-ENG",
        unit_of_measure="unit",
        cost_per_unit=Decimal("2.50"),
        reorder_point=Decimal("100.000"),
        is_active=True,
    )
    db.add_all([loc_main, loc_floor, prod_steel, prod_bolt])
    db.commit()

    yield {
        "client": client,
        "db": db,
        "session_factory": TestingSessionLocal,
        "manager": manager,
        "staff": staff,
        "mgr_headers": mgr_headers,
        "staff_headers": staff_headers,
        "wh": wh,
        "loc_main": loc_main,
        "loc_floor": loc_floor,
        "prod_steel": prod_steel,
        "prod_bolt": prod_bolt,
    }

    db.close()
    Base.metadata.drop_all(bind=engine)
    app.dependency_overrides.clear()


# ============================================================
# 1. RECEIPT — INCOMING STOCK & LEDGER
# ============================================================
def test_receipt_stock_increase_and_ledger(engine_test_env):
    """
    RECEIPT — INCOMING STOCK
    Before = 20 kg
    Receipt = +50 kg
    After = 70 kg
    Ledger: quantity_before=20, quantity_change=50, quantity_after=70, movement_type=RECEIPT
    """
    env = engine_test_env
    client = env["client"]
    db = env["db"]
    headers = env["staff_headers"]
    prod_id = env["prod_steel"].id
    loc_id = env["loc_main"].id

    # Initial stock = 20 kg
    stock = models.Stock(
        product_id=prod_id,
        location_id=loc_id,
        on_hand=Decimal("20.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Create Receipt for +50 kg
    create_resp = client.post(
        "/api/receipts",
        headers=headers,
        json={
            "product_id": prod_id,
            "to_location_id": loc_id,
            "quantity": 50.0,
            "contact": "Global Steel Supplier",
        },
    )
    assert create_resp.status_code == 201
    rcpt_id = create_resp.json()["id"]

    # Validate receipt
    val_resp = client.post(f"/api/receipts/{rcpt_id}/validate", headers=headers)
    assert val_resp.status_code == 200
    val_data = val_resp.json()
    assert val_data["status"] == "done"

    # Confirm stock = 70 kg
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()
    assert st.on_hand == Decimal("70.000")
    assert st.free_to_use == Decimal("70.000")
    assert st.reserved == Decimal("0.000")

    # Confirm Stock Ledger
    ledger = db.query(models.StockLedger).filter_by(transaction_id=rcpt_id).first()
    assert ledger is not None
    assert ledger.quantity_before == Decimal("20.000")
    assert ledger.quantity_change == Decimal("50.000")
    assert ledger.quantity_after == Decimal("70.000")
    assert ledger.movement_type == "RECEIPT"


# ============================================================
# 2. DELIVERY — OUTGOING STOCK & RESERVATION LIFECYCLE
# ============================================================
def test_delivery_lifecycle_and_reservation(engine_test_env):
    """
    DELIVERY:
    On Hand = 50, Reserved = 0, Free to Use = 50
    Delivery = 20
    READY:
      On Hand = 50, Reserved = 20, Free to Use = 30
    DONE:
      On Hand = 30, Reserved = 0, Free to Use = 30
    Ledger: DELIVERY quantity_change = -20
    """
    env = engine_test_env
    client = env["client"]
    db = env["db"]
    headers = env["staff_headers"]
    prod_id = env["prod_steel"].id
    loc_id = env["loc_main"].id

    stock = models.Stock(
        product_id=prod_id,
        location_id=loc_id,
        on_hand=Decimal("50.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Create Delivery requesting 20
    create_resp = client.post(
        "/api/deliveries",
        headers=headers,
        json={
            "product_id": prod_id,
            "from_location_id": loc_id,
            "quantity": 20.0,
            "contact": "Alpha Construction",
        },
    )
    assert create_resp.status_code == 201
    del_id = create_resp.json()["id"]

    # Mark READY (DRAFT -> READY)
    ready_resp = client.post(f"/api/deliveries/{del_id}/ready", headers=headers)
    assert ready_resp.status_code == 200
    r_data = ready_resp.json()
    assert r_data["status"] == "ready"
    assert r_data["on_hand"] == 50.0
    assert r_data["reserved"] == 20.0
    assert r_data["free_to_use"] == 30.0

    # Validate (READY -> DONE)
    val_resp = client.post(f"/api/deliveries/{del_id}/validate", headers=headers)
    assert val_resp.status_code == 200
    v_data = val_resp.json()
    assert v_data["status"] == "done"
    assert v_data["on_hand"] == 30.0
    assert v_data["reserved"] == 0.0
    assert v_data["free_to_use"] == 30.0

    # Ledger entry only on movement
    db.expire_all()
    ledger = db.query(models.StockLedger).filter_by(transaction_id=del_id).first()
    assert ledger is not None
    assert ledger.quantity_before == Decimal("50.000")
    assert ledger.quantity_change == Decimal("-20.000")
    assert ledger.quantity_after == Decimal("30.000")
    assert ledger.movement_type == "DELIVERY"


# ============================================================
# 3. DELIVERY — INSUFFICIENT STOCK & WAITING STATUS
# ============================================================
def test_delivery_insufficient_stock_waiting(engine_test_env):
    """
    If free_to_use is insufficient:
    DRAFT -> WAITING
    No stock change. No reservation.
    """
    env = engine_test_env
    client = env["client"]
    db = env["db"]
    headers = env["staff_headers"]
    prod_id = env["prod_steel"].id
    loc_id = env["loc_main"].id

    # On Hand = 10, Reserved = 5, Free to Use = 5
    stock = models.Stock(
        product_id=prod_id,
        location_id=loc_id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("5.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Requested = 20
    create_resp = client.post(
        "/api/deliveries",
        headers=headers,
        json={
            "product_id": prod_id,
            "from_location_id": loc_id,
            "quantity": 20.0,
            "contact": "Beta Builders",
        },
    )
    assert create_resp.status_code == 201
    del_id = create_resp.json()["id"]

    # Attempt to mark READY
    ready_resp = client.post(f"/api/deliveries/{del_id}/ready", headers=headers)
    assert ready_resp.status_code == 200
    r_data = ready_resp.json()
    assert r_data["status"] == "waiting"
    assert r_data["shortage"] == 15.0

    # Check DB: NO stock change, NO reservation change
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()
    assert st.on_hand == Decimal("10.000")
    assert st.reserved == Decimal("5.000")
    assert st.free_to_use == Decimal("5.000")

    # Cannot validate a WAITING delivery
    val_resp = client.post(f"/api/deliveries/{del_id}/validate", headers=headers)
    assert val_resp.status_code == 400


# ============================================================
# 4. WAITING -> READY AUTOMATION & MULTI-PRODUCT ALL-OR-NOTHING
# ============================================================
def test_waiting_to_ready_automation_multi_product(engine_test_env):
    """
    WAITING -> READY Automation:
    Multi-product delivery: Steel Rod (10 kg) and Bolt (20 units).
    When stock is partially available, delivery stays WAITING (no partial fulfillment).
    When ALL products become available, delivery automatically transitions to READY and reserves all items.
    """
    env = engine_test_env
    client = env["client"]
    db = env["db"]
    headers = env["staff_headers"]
    steel_id = env["prod_steel"].id
    bolt_id = env["prod_bolt"].id
    loc_id = env["loc_main"].id

    # Create empty stock rows
    st_steel = models.Stock(product_id=steel_id, location_id=loc_id, on_hand=Decimal("0.000"), reserved=Decimal("0.000"), version=1)
    st_bolt = models.Stock(product_id=bolt_id, location_id=loc_id, on_hand=Decimal("0.000"), reserved=Decimal("0.000"), version=1)
    db.add_all([st_steel, st_bolt])
    db.commit()

    # Create Multi-product delivery via /api/transactions
    tx_resp = client.post(
        "/api/transactions",
        headers=headers,
        json={
            "type": "DELIVERY",
            "source_location_id": loc_id,
            "party_name": "Mega Project",
            "items": [
                {"product_id": steel_id, "quantity": 10.0},
                {"product_id": bolt_id, "quantity": 20.0},
            ],
        },
    )
    assert tx_resp.status_code == 201
    tx_id = tx_resp.json()["id"]

    # Prepare -> WAITING
    prep_resp = client.post(f"/api/transactions/{tx_id}/prepare", headers=headers)
    assert prep_resp.status_code == 200
    assert prep_resp.json()["status"] == "WAITING"

    # Step 1: Receive ONLY Steel Rod (+15 kg)
    rec1 = client.post(
        "/api/receipts",
        headers=headers,
        json={"product_id": steel_id, "to_location_id": loc_id, "quantity": 15.0},
    )
    client.post(f"/api/receipts/{rec1.json()['id']}/validate", headers=headers)

    # Delivery must STILL be WAITING because Bolt has 0 stock (NO partial fulfillment!)
    db.expire_all()
    tx_check = db.query(models.Transaction).filter_by(id=tx_id).first()
    assert tx_check.status == TransactionStatus.WAITING

    # Steel reservation must NOT have been locked by the delivery yet
    st_steel_check = db.query(models.Stock).filter_by(product_id=steel_id, location_id=loc_id).first()
    assert st_steel_check.on_hand == Decimal("15.000")
    assert st_steel_check.reserved == Decimal("0.000")

    # Step 2: Receive Bolt (+25 units)
    rec2 = client.post(
        "/api/receipts",
        headers=headers,
        json={"product_id": bolt_id, "to_location_id": loc_id, "quantity": 25.0},
    )
    client.post(f"/api/receipts/{rec2.json()['id']}/validate", headers=headers)

    # NOW Delivery must automatically be READY!
    db.expire_all()
    tx_ready = db.query(models.Transaction).filter_by(id=tx_id).first()
    assert tx_ready.status == TransactionStatus.READY

    # Both products reserved
    st_steel_final = db.query(models.Stock).filter_by(product_id=steel_id, location_id=loc_id).first()
    st_bolt_final = db.query(models.Stock).filter_by(product_id=bolt_id, location_id=loc_id).first()
    assert st_steel_final.reserved == Decimal("10.000")
    assert st_bolt_final.reserved == Decimal("20.000")


# ============================================================
# 5. TRANSFER — MOVEMENT & CONSTRAINTS
# ============================================================
def test_transfer_lifecycle_and_constraints(engine_test_env):
    """
    TRANSFER:
    Source: on_hand -= qty
    Destination: on_hand += qty
    Only FREE TO USE stock may be transferred. Reserved stock cannot be transferred.
    Atomically writes TRANSFER_OUT and TRANSFER_IN ledger entries.
    Total inventory unchanged.
    """
    env = engine_test_env
    client = env["client"]
    db = env["db"]
    headers = env["staff_headers"]
    prod_id = env["prod_steel"].id
    src_id = env["loc_main"].id
    dst_id = env["loc_floor"].id

    # Source has 50 kg on hand, 20 kg reserved -> Free to use = 30 kg
    st_src = models.Stock(product_id=prod_id, location_id=src_id, on_hand=Decimal("50.000"), reserved=Decimal("20.000"), version=1)
    st_dst = models.Stock(product_id=prod_id, location_id=dst_id, on_hand=Decimal("10.000"), reserved=Decimal("0.000"), version=1)
    db.add_all([st_src, st_dst])
    db.commit()

    # 1. Attempt transfer of 35 kg (> 30 kg free_to_use) -> Must be rejected!
    trf_bad = client.post(
        "/api/transfers",
        headers=headers,
        json={"from_location_id": src_id, "to_location_id": dst_id, "product_id": prod_id, "quantity": 35.0},
    )
    bad_id = trf_bad.json()["id"]
    ready_bad = client.post(f"/api/transfers/{bad_id}/ready", headers=headers)
    assert ready_bad.status_code == 400

    # 2. Transfer 25 kg (<= 30 kg free_to_use) -> Valid
    trf_ok = client.post(
        "/api/transfers",
        headers=headers,
        json={"from_location_id": src_id, "to_location_id": dst_id, "product_id": prod_id, "quantity": 25.0},
    )
    ok_id = trf_ok.json()["id"]

    val_trf = client.post(f"/api/transfers/{ok_id}/validate", headers=headers)
    assert val_trf.status_code == 200

    # Source: 50 - 25 = 25
    # Destination: 10 + 25 = 35
    # Total inventory before: 60 kg; Total inventory after: 60 kg (UNCHANGED)
    db.expire_all()
    st_src_after = db.query(models.Stock).filter_by(product_id=prod_id, location_id=src_id).first()
    st_dst_after = db.query(models.Stock).filter_by(product_id=prod_id, location_id=dst_id).first()

    assert st_src_after.on_hand == Decimal("25.000")
    assert st_src_after.reserved == Decimal("20.000")
    assert st_dst_after.on_hand == Decimal("35.000")
    assert (st_src_after.on_hand + st_dst_after.on_hand) == Decimal("60.000")

    # Check atomic ledger entries: TRANSFER_OUT and TRANSFER_IN
    ledgers = db.query(models.StockLedger).filter_by(transaction_id=ok_id).all()
    assert len(ledgers) == 2
    types = {l.movement_type for l in ledgers}
    assert types == {"TRANSFER_OUT", "TRANSFER_IN"}


# ============================================================
# 6. ADJUSTMENT — DELTA & RESERVATION CONSTRAINT
# ============================================================
def test_adjustment_delta_and_reserved_constraint(engine_test_env):
    """
    ADJUSTMENT:
    delta = physical_count - current_on_hand
    Never allow: on_hand < reserved
    Manager validates.
    """
    env = engine_test_env
    client = env["client"]
    db = env["db"]
    mgr_headers = env["mgr_headers"]
    staff_headers = env["staff_headers"]
    prod_id = env["prod_steel"].id
    loc_id = env["loc_main"].id

    # Stock: on_hand = 80, reserved = 30
    stock = models.Stock(
        product_id=prod_id,
        location_id=loc_id,
        on_hand=Decimal("80.000"),
        reserved=Decimal("30.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # 1. Physical count = 25 (violates reserved 30) -> REJECTED
    adj_invalid = client.post(
        "/api/adjustments",
        headers=staff_headers,
        json={"location_id": loc_id, "product_id": prod_id, "physical_count": 25.0, "reason": "Lost"},
    )
    inv_id = adj_invalid.json()["id"]
    val_inv = client.post(f"/api/adjustments/{inv_id}/validate", headers=mgr_headers)
    assert val_inv.status_code == 400
    assert "reserved" in val_inv.json()["detail"].lower()

    # 2. Physical count = 77 (Delta = -3 kg, Damaged) -> SUCCESS
    adj_valid = client.post(
        "/api/adjustments",
        headers=staff_headers,
        json={"location_id": loc_id, "product_id": prod_id, "physical_count": 77.0, "reason": "Damaged"},
    )
    val_id = adj_valid.json()["id"]
    val_ok = client.post(f"/api/adjustments/{val_id}/validate", headers=mgr_headers)
    assert val_ok.status_code == 200

    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()
    assert st.on_hand == Decimal("77.000")
    assert st.reserved == Decimal("30.000")

    ledger = db.query(models.StockLedger).filter_by(transaction_id=val_id).first()
    assert ledger.quantity_before == Decimal("80.000")
    assert ledger.quantity_change == Decimal("-3.000")
    assert ledger.quantity_after == Decimal("77.000")
    assert ledger.movement_type == "ADJUSTMENT"


# ============================================================
# 7. IDEMPOTENCY & IMMUTABILITY OF DONE
# ============================================================
def test_idempotency_and_done_immutability(engine_test_env):
    """
    IDEMPOTENCY:
    Validation endpoints must support Idempotency-Key.
    Duplicate validation must NOT mutate inventory twice.
    A DONE transaction must never be validated again.
    """
    env = engine_test_env
    client = env["client"]
    db = env["db"]
    headers = env["staff_headers"]
    prod_id = env["prod_steel"].id
    loc_id = env["loc_main"].id

    stock = models.Stock(
        product_id=prod_id,
        location_id=loc_id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()

    # Create Receipt for 40 kg
    rec_resp = client.post(
        "/api/receipts",
        headers=headers,
        json={"product_id": prod_id, "to_location_id": loc_id, "quantity": 40.0},
    )
    rec_id = rec_resp.json()["id"]

    idemp_headers = {**headers, "Idempotency-Key": "unique-idem-token-42"}

    # 1. First validation call with Idempotency-Key
    val1 = client.post(f"/api/receipts/{rec_id}/validate", headers=idemp_headers)
    assert val1.status_code == 200

    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()
    assert st.on_hand == Decimal("50.000")
    assert db.query(models.StockLedger).filter_by(transaction_id=rec_id).count() == 1

    # 2. Duplicate validation with identical Idempotency-Key -> 200 OK without re-mutation
    val2 = client.post(f"/api/receipts/{rec_id}/validate", headers=idemp_headers)
    assert val2.status_code == 200

    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()
    assert st.on_hand == Decimal("50.000")  # Remains 50 (NOT 90!)
    assert db.query(models.StockLedger).filter_by(transaction_id=rec_id).count() == 1

    # 3. Third validation with DIFFERENT key (or no key) -> Must be rejected (400 Bad Request)
    val3 = client.post(
        f"/api/receipts/{rec_id}/validate",
        headers={**headers, "Idempotency-Key": "another-key-99"},
    )
    assert val3.status_code == 400

    # 4. DONE transaction cannot be canceled
    cancel_resp = client.post(f"/api/receipts/{rec_id}/cancel", headers=headers)
    assert cancel_resp.status_code == 400


# ============================================================
# 8. CONCURRENCY: SIMULTANEOUS DELIVERIES RACE CONDITION
# ============================================================
def test_simultaneous_deliveries_concurrency(engine_test_env):
    """
    Initial stock = 10.
    User A delivers 8.
    User B simultaneously delivers 8.
    The system must never produce:
      - negative stock
      - overselling
      - invalid reservations
      - duplicate ledger entries
    """
    env = engine_test_env
    session_factory = env["session_factory"]
    manager = env["manager"]
    prod_id = env["prod_steel"].id
    loc_id = env["loc_main"].id

    db_init = session_factory()
    stock = models.Stock(
        product_id=prod_id,
        location_id=loc_id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db_init.add(stock)
    db_init.commit()

    # Create Delivery A (8 kg) and Delivery B (8 kg)
    tx_a = models.Transaction(
        reference="DEL-CONCUR-1",
        type=TransactionType.DELIVERY,
        status=TransactionStatus.DRAFT,
        source_location_id=loc_id,
        created_by=manager.id,
    )
    tx_b = models.Transaction(
        reference="DEL-CONCUR-2",
        type=TransactionType.DELIVERY,
        status=TransactionStatus.DRAFT,
        source_location_id=loc_id,
        created_by=manager.id,
    )
    db_init.add_all([tx_a, tx_b])
    db_init.flush()

    db_init.add(models.TransactionItem(transaction_id=tx_a.id, product_id=prod_id, quantity=Decimal("8.000")))
    db_init.add(models.TransactionItem(transaction_id=tx_b.id, product_id=prod_id, quantity=Decimal("8.000")))
    db_init.commit()

    id_a = tx_a.id
    id_b = tx_b.id
    db_init.close()

    def run_prepare(tx_id: int):
        thread_db = session_factory()
        try:
            user = thread_db.query(models.User).filter_by(id=manager.id).first()
            engine = InventoryTransactionEngine(thread_db)
            return engine.prepare_delivery(tx_id, user).status
        finally:
            thread_db.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        f_a = pool.submit(run_prepare, id_a)
        f_b = pool.submit(run_prepare, id_b)
        res_a = f_a.result()
        res_b = f_b.result()

    verify_db = session_factory()
    tx_a_after = verify_db.query(models.Transaction).filter_by(id=id_a).first()
    tx_b_after = verify_db.query(models.Transaction).filter_by(id=id_b).first()
    st_after = verify_db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()

    # Exactly one READY, one WAITING
    assert {tx_a_after.status, tx_b_after.status} == {TransactionStatus.READY, TransactionStatus.WAITING}

    # Reserved must be exactly 8 (NOT 16!), free must be 2
    assert st_after.reserved == Decimal("8.000")
    assert st_after.on_hand == Decimal("10.000")
    assert st_after.free_to_use == Decimal("2.000")

    # Validate the READY one
    ready_id = id_a if tx_a_after.status == TransactionStatus.READY else id_b
    user = verify_db.query(models.User).filter_by(id=manager.id).first()
    engine = InventoryTransactionEngine(verify_db)
    engine.validate_transaction(ready_id, user)

    verify_db.refresh(st_after)
    assert st_after.on_hand == Decimal("2.000")
    assert st_after.reserved == Decimal("0.000")
    assert st_after.free_to_use == Decimal("2.000")

    # Exactly one ledger entry
    assert verify_db.query(models.StockLedger).filter_by(product_id=prod_id).count() == 1
    verify_db.close()
