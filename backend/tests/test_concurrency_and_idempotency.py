import concurrent.futures
import pytest
from decimal import Decimal
import datetime
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
def concurrent_setup():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False, "timeout": 30},
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

    # Create Manager User
    manager = models.User(
        name="Sarah Manager",
        email="manager@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    db.add(manager)

    # Create Staff User
    staff = models.User(
        name="Bob Staff",
        email="staff@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="WAREHOUSE_STAFF",
        is_active=True,
    )
    db.add(staff)
    db.commit()
    db.refresh(manager)
    db.refresh(staff)

    # Warehouse & Location
    wh = models.Warehouse(name="Central Distribution", short_code="CD-01")
    db.add(wh)
    db.commit()
    db.refresh(wh)

    loc = models.Location(warehouse_id=wh.id, name="Bin 1", short_code="BIN-1")
    db.add(loc)
    db.commit()
    db.refresh(loc)

    # Product
    prod = models.Product(
        name="High Strength Steel Rod",
        sku="HSS-80",
        cost_per_unit=Decimal("150.00"),
        unit_of_measure="kg",
        reorder_point=Decimal("10.000"),
        is_active=True,
    )
    db.add(prod)
    db.commit()
    db.refresh(prod)

    # Seed Initial Stock = 10 (Section 48 requirement)
    stock = models.Stock(
        product_id=prod.id,
        location_id=loc.id,
        on_hand=Decimal("10.000"),
        reserved=Decimal("0.000"),
        version=1,
    )
    db.add(stock)
    db.commit()
    db.refresh(stock)

    yield {
        "engine": engine,
        "session_factory": TestingSessionLocal,
        "db": db,
        "client": client,
        "manager": manager,
        "staff": staff,
        "product": prod,
        "location": loc,
        "stock": stock,
    }

    db.close()
    app.dependency_overrides.clear()


# ============================================================
# 48. CRITICAL CONCURRENCY TEST
# ============================================================
def test_critical_concurrency_race_condition(concurrent_setup):
    """
    Section 48: CRITICAL CONCURRENCY TEST
    Test:
      Stock = 10
      User A tries to deliver 8.
      User B simultaneously tries to deliver 8.

    The system MUST NOT allow:
      - negative stock
      - overselling
      - invalid reservations
      - duplicate ledger entries

    Use database locking and transactions.
    """
    setup = concurrent_setup
    session_factory = setup["session_factory"]
    prod_id = setup["product"].id
    loc_id = setup["location"].id
    manager_id = setup["manager"].id

    db_main = setup["db"]

    # Create Delivery A for 8 units
    tx_a = models.Transaction(
        reference="DEL-CONCUR-A",
        type=TransactionType.DELIVERY,
        status=TransactionStatus.DRAFT,
        source_location_id=loc_id,
        contact="Client Alpha",
        created_by=manager_id,
    )
    db_main.add(tx_a)
    db_main.flush()
    item_a = models.TransactionItem(
        transaction_id=tx_a.id,
        product_id=prod_id,
        quantity=Decimal("8.000"),
    )
    db_main.add(item_a)

    # Create Delivery B for 8 units
    tx_b = models.Transaction(
        reference="DEL-CONCUR-B",
        type=TransactionType.DELIVERY,
        status=TransactionStatus.DRAFT,
        source_location_id=loc_id,
        contact="Client Beta",
        created_by=manager_id,
    )
    db_main.add(tx_b)
    db_main.flush()
    item_b = models.TransactionItem(
        transaction_id=tx_b.id,
        product_id=prod_id,
        quantity=Decimal("8.000"),
    )
    db_main.add(item_b)
    db_main.commit()

    tx_a_id = tx_a.id
    tx_b_id = tx_b.id

    # Function executed by worker threads
    def prepare_in_thread(tx_id: int):
        thread_db = session_factory()
        try:
            user = thread_db.query(models.User).filter(models.User.id == manager_id).first()
            engine = InventoryTransactionEngine(thread_db)
            res = engine.prepare_delivery(tx_id, user)
            return res.status
        finally:
            thread_db.close()

    # Run simultaneously in 2 threads
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        future_a = executor.submit(prepare_in_thread, tx_a_id)
        future_b = executor.submit(prepare_in_thread, tx_b_id)
        status_a = future_a.result()
        status_b = future_b.result()

    # Re-fetch from DB
    db_main.expire_all()
    tx_a_after = db_main.query(models.Transaction).filter(models.Transaction.id == tx_a_id).first()
    tx_b_after = db_main.query(models.Transaction).filter(models.Transaction.id == tx_b_id).first()
    stock_after = db_main.query(models.Stock).filter(
        models.Stock.product_id == prod_id,
        models.Stock.location_id == loc_id,
    ).first()

    # Section 48 Assertions:
    # 1. Exactly one must be READY, and exactly one must be WAITING
    statuses = {tx_a_after.status, tx_b_after.status}
    assert statuses == {TransactionStatus.READY, TransactionStatus.WAITING}, (
        f"Expected one READY and one WAITING, got {tx_a_after.status} and {tx_b_after.status}"
    )

    # 2. NO OVERSELLING & NO INVALID RESERVATIONS:
    # Reserved stock must be exactly 8, NOT 16!
    assert stock_after.reserved == Decimal("8.000")
    # On hand remains 10 (not yet validated)
    assert stock_after.on_hand == Decimal("10.000")
    # Free to use is 2 (10 - 8)
    assert stock_after.free_to_use == Decimal("2.000")

    # 3. NO NEGATIVE STOCK:
    assert stock_after.on_hand >= Decimal("0.000")
    assert stock_after.free_to_use >= Decimal("0.000")

    # Now validate the READY delivery
    ready_tx = tx_a_after if tx_a_after.status == TransactionStatus.READY else tx_b_after
    waiting_tx = tx_b_after if tx_a_after.status == TransactionStatus.READY else tx_a_after

    engine_main = InventoryTransactionEngine(db_main)
    manager_user = db_main.query(models.User).filter(models.User.id == manager_id).first()

    engine_main.validate_transaction(ready_tx.id, manager_user)
    db_main.refresh(stock_after)

    # After validation:
    # on_hand was 10, delivered 8 -> on_hand is 2
    # reserved was 8 -> reserved is 0
    # free_to_use is 2
    assert stock_after.on_hand == Decimal("2.000")
    assert stock_after.reserved == Decimal("0.000")
    assert stock_after.free_to_use == Decimal("2.000")

    # 4. NO DUPLICATE LEDGER ENTRIES:
    ledger_entries = db_main.query(models.StockLedger).filter(
        models.StockLedger.product_id == prod_id,
        models.StockLedger.location_id == loc_id,
    ).all()
    assert len(ledger_entries) == 1
    assert ledger_entries[0].transaction_id == ready_tx.id
    assert ledger_entries[0].quantity_change == Decimal("-8.000")
    assert ledger_entries[0].quantity_before == Decimal("10.000")
    assert ledger_entries[0].quantity_after == Decimal("2.000")

    # Verify that the WAITING delivery CANNOT be validated (since stock=2, needed=8)
    with pytest.raises(Exception):
        engine_main.validate_transaction(waiting_tx.id, manager_user)

    # Verify on_hand is still 2 and ledger count remains 1
    db_main.refresh(stock_after)
    assert stock_after.on_hand == Decimal("2.000")
    ledger_count_final = db_main.query(models.StockLedger).filter(
        models.StockLedger.product_id == prod_id,
    ).count()
    assert ledger_count_final == 1


# ============================================================
# 47. IDEMPOTENCY TEST
# ============================================================
def test_idempotent_transaction_validation(concurrent_setup):
    """
    Section 47: Idempotency
    A transaction must never mutate inventory twice or generate duplicate ledger entries.
    """
    setup = concurrent_setup
    db = setup["db"]
    prod = setup["product"]
    loc = setup["location"]
    manager = setup["manager"]

    # Create a Receipt for 50 kg
    tx = models.Transaction(
        reference="REC-IDEMP-001",
        type=TransactionType.RECEIPT,
        status=TransactionStatus.READY,
        destination_location_id=loc.id,
        created_by=manager.id,
    )
    db.add(tx)
    db.flush()
    item = models.TransactionItem(
        transaction_id=tx.id,
        product_id=prod.id,
        quantity=Decimal("50.000"),
    )
    db.add(item)
    db.commit()

    engine = InventoryTransactionEngine(db)
    idemp_key = "idemp-key-unique-999"

    # First validation with key (engine records idempotency automatically)
    res1 = engine.validate_transaction(tx.id, manager, idempotency_key=idemp_key)
    assert res1.status == TransactionStatus.DONE
    db.commit()

    # Check stock after 1st validation (initial 10 + 50 = 60)
    stock = db.query(models.Stock).filter(models.Stock.product_id == prod.id).first()
    assert stock.on_hand == Decimal("60.000")

    ledger_count_1 = db.query(models.StockLedger).filter(models.StockLedger.transaction_id == tx.id).count()
    assert ledger_count_1 == 1

    # Second validation with the SAME idempotency key
    res2 = engine.validate_transaction(tx.id, manager, idempotency_key=idemp_key)
    assert res2.status == TransactionStatus.DONE

    # Stock must remain 60 (NOT 110!)
    db.refresh(stock)
    assert stock.on_hand == Decimal("60.000")

    # Ledger entries must still be exactly 1
    ledger_count_2 = db.query(models.StockLedger).filter(models.StockLedger.transaction_id == tx.id).count()
    assert ledger_count_2 == 1


# ============================================================
# 47. AUTHORIZATION & RBAC TEST
# ============================================================
def test_authorization_role_enforcement(concurrent_setup):
    """
    Section 47: Authorization & RBAC
    Warehouse Staff can create adjustments, but only Inventory Manager can validate them.
    """
    setup = concurrent_setup
    client = setup["client"]
    manager = setup["manager"]
    staff = setup["staff"]
    prod = setup["product"]
    loc = setup["location"]

    manager_token = security.create_access_token(data={"sub": manager.email, "role": manager.role})
    staff_token = security.create_access_token(data={"sub": staff.email, "role": staff.role})

    # Staff creates an adjustment
    adj_resp = client.post(
        "/api/adjustments",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={
            "product_id": prod.id,
            "location_id": loc.id,
            "physical_count": 8.0,
            "reason": "Damaged",
        },
    )
    assert adj_resp.status_code == 201
    adj_id = adj_resp.json()["id"]

    # Staff attempts to validate the adjustment -> Must be rejected 403 Forbidden!
    staff_val_resp = client.post(
        f"/api/adjustments/{adj_id}/validate",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert staff_val_resp.status_code == 403

    # Manager validates the adjustment -> Succeeds 200 OK!
    mgr_val_resp = client.post(
        f"/api/adjustments/{adj_id}/validate",
        headers={"Authorization": f"Bearer {manager_token}"},
    )
    assert mgr_val_resp.status_code == 200
    assert str(mgr_val_resp.json()["status"]).upper() == "DONE"


# ============================================================
# 47. DUPLICATE SKU TEST
# ============================================================
def test_duplicate_sku_rejection(concurrent_setup):
    """
    Section 47: Duplicate SKU
    SKU must be unique. Attempting to create duplicate SKU must be rejected.
    """
    setup = concurrent_setup
    client = setup["client"]
    manager = setup["manager"]
    manager_token = security.create_access_token(data={"sub": manager.email, "role": manager.role})

    # Create a new product with SKU "SKU-TEST-99"
    resp1 = client.post(
        "/api/products",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={
            "name": "Copper Pipe 15mm",
            "sku": "SKU-TEST-99",
            "cost_per_unit": 45.0,
            "unit_of_measure": "meter",
            "reorder_point": 5.0,
        },
    )
    assert resp1.status_code == 201

    # Attempt to create another product with the identical SKU "SKU-TEST-99"
    resp2 = client.post(
        "/api/products",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={
            "name": "Another Copper Pipe",
            "sku": "SKU-TEST-99",
            "cost_per_unit": 50.0,
            "unit_of_measure": "meter",
            "reorder_point": 5.0,
        },
    )
    # Must reject with 400 Bad Request or 409 Conflict
    assert resp2.status_code in (400, 409)
