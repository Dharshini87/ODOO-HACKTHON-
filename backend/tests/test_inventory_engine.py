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
from app.services.reference_service import generate_transaction_reference


@pytest.fixture(scope="function")
def engine_client_and_db():
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

    # Seed users
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

    # Seed Category, Product, Warehouse, and 2 Locations
    cat = models.Category(name="Electronics", is_active=True)
    wh = models.Warehouse(name="Main Warehouse", short_code="WH", is_active=True)
    db.add_all([cat, wh])
    db.commit()

    prod = models.Product(
        name="Industrial Sensor",
        sku="SENS-IND-01",
        category_id=cat.id,
        cost_per_unit=Decimal("50.00"),
        reorder_point=Decimal("10.000"),
        is_active=True,
    )
    loc1 = models.Location(warehouse_id=wh.id, name="Aisle 1", short_code="A1", is_active=True)
    loc2 = models.Location(warehouse_id=wh.id, name="Aisle 2", short_code="A2", is_active=True)
    db.add_all([prod, loc1, loc2])
    db.commit()

    yield client, db, manager_token, staff_token, prod.id, loc1.id, loc2.id

    db.close()
    Base.metadata.drop_all(bind=engine)
    app.dependency_overrides.clear()


# ============================================================
# SECTION 41: REFERENCES GENERATION
# ============================================================

def test_reference_generation_mappings(engine_client_and_db):
    """Section 41: Reference formatting and sequence generation (no MAX(id)+1)."""
    _, db, _, _, _, _, _ = engine_client_and_db

    ref_in = generate_transaction_reference(db, TransactionType.RECEIPT, "WH")
    assert ref_in == "WH/IN/0001"

    ref_out = generate_transaction_reference(db, TransactionType.DELIVERY, "WH")
    assert ref_out == "WH/OUT/0001"

    ref_tr = generate_transaction_reference(db, TransactionType.TRANSFER, "WH")
    assert ref_tr == "WH/TR/0001"

    ref_adj = generate_transaction_reference(db, TransactionType.ADJUSTMENT, "WH")
    assert ref_adj == "WH/ADJ/0001"

    # Next receipt sequence increments
    ref_in2 = generate_transaction_reference(db, TransactionType.RECEIPT, "WH")
    assert ref_in2 == "WH/IN/0002"


# ============================================================
# SECTION 18: 13-STEP INVENTORY ENGINE FLOWS
# ============================================================

def test_receipt_13_step_validation_flow(engine_client_and_db):
    """Section 18: Receipt validation flow, stock on_hand increase, ledger write."""
    client, db, mgr_tok, staff_tok, prod_id, loc1_id, _ = engine_client_and_db
    headers = {"Authorization": f"Bearer {staff_tok}"}

    # 1. Create Receipt transaction
    create_res = client.post(
        "/api/transactions",
        json={
            "type": "RECEIPT",
            "destination_location_id": loc1_id,
            "party_name": "Sensor Supplies Inc",
            "items": [{"product_id": prod_id, "quantity": 100.0}],
        },
        headers=headers,
    )
    assert create_res.status_code == 201
    tx_data = create_res.json()
    tx_id = tx_data["id"]
    assert tx_data["reference"].startswith("WH/IN/")
    assert tx_data["status"] == "DRAFT"

    # Prior to validation: on_hand = 0
    stock_before = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    assert stock_before is None or stock_before.on_hand == 0

    # 2. Validate Receipt via 13-step transaction engine
    val_res = client.post(f"/api/transactions/{tx_id}/validate", headers=headers)
    assert val_res.status_code == 200
    val_data = val_res.json()
    assert val_data["status"] == "DONE"

    # Verify Stock row updated
    stock_after = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    assert stock_after is not None
    assert stock_after.on_hand == Decimal("100.000")
    assert stock_after.reserved == Decimal("0.000")
    assert stock_after.free_to_use == Decimal("100.000")

    # Verify Ledger entry written (Section 18 step 11)
    ledger_entry = db.query(models.StockLedger).filter_by(transaction_id=tx_id).first()
    assert ledger_entry is not None
    assert ledger_entry.quantity_change == Decimal("100.000")
    assert ledger_entry.running_balance == Decimal("100.000")
    assert ledger_entry.movement_type == "RECEIPT"

    # Verify Immutability of DONE (Section 16)
    re_val = client.post(f"/api/transactions/{tx_id}/validate", headers=headers)
    assert re_val.status_code == 400


def test_delivery_reservation_and_waiting_flows(engine_client_and_db):
    """Section 16, 17, 18: Delivery reservation, waiting state on insufficient stock."""
    client, db, mgr_tok, staff_tok, prod_id, loc1_id, _ = engine_client_and_db
    headers = {"Authorization": f"Bearer {staff_tok}"}

    # First receive 50 units into loc1
    rcpt = client.post(
        "/api/transactions",
        json={
            "type": "RECEIPT",
            "destination_location_id": loc1_id,
            "items": [{"product_id": prod_id, "quantity": 50.0}],
        },
        headers=headers,
    ).json()
    client.post(f"/api/transactions/{rcpt['id']}/validate", headers=headers)

    # 1. Create Delivery requesting 30 units (Sufficient stock)
    del1 = client.post(
        "/api/transactions",
        json={
            "type": "DELIVERY",
            "source_location_id": loc1_id,
            "party_name": "Acme Corp",
            "items": [{"product_id": prod_id, "quantity": 30.0}],
        },
        headers=headers,
    ).json()
    del1_id = del1["id"]

    # Prepare delivery (Section 16 & 17: DRAFT -> READY, reserve quantity)
    prep_res = client.post(f"/api/transactions/{del1_id}/prepare", headers=headers)
    assert prep_res.status_code == 200
    assert prep_res.json()["status"] == "READY"

    stock_res = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    assert stock_res.on_hand == Decimal("50.000")
    assert stock_res.reserved == Decimal("30.000")
    assert stock_res.free_to_use == Decimal("20.000")

    # 2. Create another delivery requesting 25 units (Available is only 20 free_to_use)
    del2 = client.post(
        "/api/transactions",
        json={
            "type": "DELIVERY",
            "source_location_id": loc1_id,
            "party_name": "Beta LLC",
            "items": [{"product_id": prod_id, "quantity": 25.0}],
        },
        headers=headers,
    ).json()
    del2_id = del2["id"]

    # Prepare delivery 2 -> Insufficient free stock -> status WAITING
    prep_res2 = client.post(f"/api/transactions/{del2_id}/prepare", headers=headers)
    assert prep_res2.status_code == 200
    assert prep_res2.json()["status"] == "WAITING"

    # 3. Validate Delivery 1 (READY -> DONE: decrease on_hand, release reservation)
    val_del1 = client.post(f"/api/transactions/{del1_id}/validate", headers=headers)
    assert val_del1.status_code == 200
    assert val_del1.json()["status"] == "DONE"

    db.expire_all()
    stock_after_del = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    assert stock_after_del.on_hand == Decimal("20.000")
    assert stock_after_del.reserved == Decimal("0.000")
    assert stock_after_del.free_to_use == Decimal("20.000")


def test_transfer_deterministic_locking_flow(engine_client_and_db):
    """Section 18: Transfer flow between two locations with deterministic ordering."""
    client, db, mgr_tok, staff_tok, prod_id, loc1_id, loc2_id = engine_client_and_db
    headers = {"Authorization": f"Bearer {staff_tok}"}

    # Initial stock in loc1 = 40
    rcpt = client.post(
        "/api/transactions",
        json={
            "type": "RECEIPT",
            "destination_location_id": loc1_id,
            "items": [{"product_id": prod_id, "quantity": 40.0}],
        },
        headers=headers,
    ).json()
    client.post(f"/api/transactions/{rcpt['id']}/validate", headers=headers)

    # Transfer 15 units from loc1 to loc2
    tr_res = client.post(
        "/api/transactions",
        json={
            "type": "TRANSFER",
            "source_location_id": loc1_id,
            "destination_location_id": loc2_id,
            "items": [{"product_id": prod_id, "quantity": 15.0}],
        },
        headers=headers,
    )
    assert tr_res.status_code == 201
    tr_id = tr_res.json()["id"]

    val_tr = client.post(f"/api/transactions/{tr_id}/validate", headers=headers)
    assert val_tr.status_code == 200

    s1 = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    s2 = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc2_id).first()
    assert s1.on_hand == Decimal("25.000")
    assert s2.on_hand == Decimal("15.000")

    # 2 Ledger entries written
    ledgers = db.query(models.StockLedger).filter_by(transaction_id=tr_id).all()
    assert len(ledgers) == 2


def test_adjustment_validation_and_constraints(engine_client_and_db):
    """Section 18 & 42: Adjustment flow, physical count, reason required, cannot reduce below reserved."""
    client, db, mgr_tok, staff_tok, prod_id, loc1_id, _ = engine_client_and_db
    mgr_headers = {"Authorization": f"Bearer {mgr_tok}"}

    # Initial stock = 20, reserved = 10
    stock = models.Stock(product_id=prod_id, location_id=loc1_id, on_hand=Decimal("20.000"), reserved=Decimal("10.000"))
    db.add(stock)
    db.commit()

    # 1. Adjustment without reason fails (Section 42)
    bad_adj = client.post(
        "/api/transactions",
        json={
            "type": "ADJUSTMENT",
            "source_location_id": loc1_id,
            "reason": "",
            "items": [{"product_id": prod_id, "quantity": 15.0}],
        },
        headers=mgr_headers,
    )
    assert bad_adj.status_code == 400

    # 2. Adjustment reducing below reserved fails (Section 42: count = 5 < reserved = 10)
    adj_too_low = client.post(
        "/api/transactions",
        json={
            "type": "ADJUSTMENT",
            "source_location_id": loc1_id,
            "reason": "Damaged goods cycle count",
            "items": [{"product_id": prod_id, "quantity": 5.0}],
        },
        headers=mgr_headers,
    ).json()
    val_low = client.post(f"/api/transactions/{adj_too_low['id']}/validate", headers=mgr_headers)
    assert val_low.status_code == 400
    assert "cannot reduce stock below reserved" in val_low.json()["detail"].lower()

    # 3. Valid adjustment (count = 25 > 20: delta = +5)
    valid_adj = client.post(
        "/api/transactions",
        json={
            "type": "ADJUSTMENT",
            "source_location_id": loc1_id,
            "reason": "Quarterly physical count surplus",
            "items": [{"product_id": prod_id, "quantity": 25.0}],
        },
        headers=mgr_headers,
    ).json()
    val_good = client.post(f"/api/transactions/{valid_adj['id']}/validate", headers=mgr_headers)
    assert val_good.status_code == 200

    s_updated = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    assert s_updated.on_hand == Decimal("25.000")


# ============================================================
# SECTION 40: IDEMPOTENCY KEY TESTS
# ============================================================

def test_idempotency_prevents_duplicate_mutation(engine_client_and_db):
    """Section 40: Idempotency-Key prevents duplicate mutation on retries / double-taps."""
    client, db, mgr_tok, staff_tok, prod_id, loc1_id, _ = engine_client_and_db
    headers = {
        "Authorization": f"Bearer {staff_tok}",
        "Idempotency-Key": "test-uuid-idemp-12345",
    }

    # Create receipt of 20 units
    rcpt = client.post(
        "/api/transactions",
        json={
            "type": "RECEIPT",
            "destination_location_id": loc1_id,
            "items": [{"product_id": prod_id, "quantity": 20.0}],
        },
        headers=headers,
    ).json()
    tx_id = rcpt["id"]

    # 1. First validation request (mutates stock from 0 to 20)
    res1 = client.post(f"/api/transactions/{tx_id}/validate", headers=headers)
    assert res1.status_code == 200
    assert res1.json()["status"] == "DONE"

    stock1 = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    assert stock1.on_hand == Decimal("20.000")

    # 2. Duplicate validation request with SAME Idempotency-Key (e.g. network retry / double tap)
    res2 = client.post(f"/api/transactions/{tx_id}/validate", headers=headers)
    assert res2.status_code == 200
    assert res2.json()["status"] == "DONE"

    # Stock must NOT be mutated twice!
    stock2 = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc1_id).first()
    assert stock2.on_hand == Decimal("20.000")

    # Only 1 ledger entry written
    ledger_count = db.query(models.StockLedger).filter_by(transaction_id=tx_id).count()
    assert ledger_count == 1
