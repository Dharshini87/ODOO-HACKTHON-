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
def receipts_client_and_db():
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
        name="Manager User",
        email="manager@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    staff1 = models.User(
        name="Staff 1",
        email="staff1@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="WAREHOUSE_STAFF",
        is_active=True,
    )
    staff2 = models.User(
        name="Staff 2",
        email="staff2@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="WAREHOUSE_STAFF",
        is_active=True,
    )
    db.add_all([manager, staff1, staff2])
    db.commit()

    manager_token = security.create_access_token(
        {"sub": manager.email, "role": manager.role, "user_id": manager.id}
    )
    staff1_token = security.create_access_token(
        {"sub": staff1.email, "role": staff1.role, "user_id": staff1.id}
    )
    staff2_token = security.create_access_token(
        {"sub": staff2.email, "role": staff2.role, "user_id": staff2.id}
    )

    # Seed master data: Product and Warehouse Location
    wh = models.Warehouse(name="Central WH", short_code="WH", is_active=True)
    db.add(wh)
    db.commit()

    loc = models.Location(warehouse_id=wh.id, name="Raw Materials Bay", short_code="RM-01", is_active=True)
    prod = models.Product(
        name="Steel Rod",
        sku="STL-ROD-100",
        unit_of_measure="kg",
        cost_per_unit=Decimal("20.00"),
        reorder_point=Decimal("50.000"),
        is_active=True,
    )
    db.add_all([loc, prod])
    db.commit()

    yield client, db, manager_token, staff1_token, staff2_token, prod.id, loc.id

    db.close()
    Base.metadata.drop_all(bind=engine)
    app.dependency_overrides.clear()


def test_receipt_full_lifecycle_flow(receipts_client_and_db):
    """
    Section 19:
    Example: Receive 100 kg Steel Rod.
    Flow: DRAFT -> READY -> DONE
    When validated: on_hand += 100
    Create ledger:
      quantity_before = 0
      quantity_change = +100
      quantity_after = 100
      movement_type = RECEIPT
    """
    client, db, mgr_tok, staff1_tok, _, prod_id, loc_id = receipts_client_and_db
    headers = {"Authorization": f"Bearer {staff1_tok}"}

    # Initial stock before receipt = 0
    stock_0 = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()
    assert stock_0 is None or stock_0.on_hand == 0

    # 1. Create Receipt in DRAFT
    create_payload = {
        "product_id": prod_id,
        "to_location_id": loc_id,
        "quantity": 100.0,
        "contact": "Apex Steel Works",
    }
    create_res = client.post("/receipts", json=create_payload, headers=headers)
    assert create_res.status_code == 201
    rcpt = create_res.json()
    assert rcpt["status"] == "draft"
    assert rcpt["reference"].startswith("WH/IN/")
    assert rcpt["product_name"] == "Steel Rod"
    assert rcpt["quantity"] == 100.0
    rcpt_id = rcpt["id"]

    # 2. Transition DRAFT -> READY
    ready_res = client.post(f"/receipts/{rcpt_id}/ready", headers=headers)
    assert ready_res.status_code == 200
    assert ready_res.json()["status"] == "ready"

    # 3. Transition READY -> DONE (Validate)
    val_res = client.post(f"/receipts/{rcpt_id}/validate", headers=headers)
    assert val_res.status_code == 200
    val_data = val_res.json()
    assert val_data["status"] == "done"
    assert val_data["done_at"] is not None

    # Check ledger details in response
    ledger_info = val_data["ledger"]
    assert ledger_info is not None
    assert ledger_info["quantity_before"] == 0.0
    assert ledger_info["quantity_change"] == 100.0
    assert ledger_info["quantity_after"] == 100.0
    assert ledger_info["movement_type"] == "RECEIPT"

    # Verify Stock row in database
    db.expire_all()
    stock = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc_id).first()
    assert stock is not None
    assert stock.on_hand == Decimal("100.000")
    assert stock.reserved == Decimal("0.000")
    assert stock.free_to_use == Decimal("100.000")

    # Verify StockLedger in database
    ledger_row = db.query(models.StockLedger).filter_by(transaction_id=rcpt_id).first()
    assert ledger_row is not None
    assert ledger_row.quantity_before == Decimal("0.000")
    assert ledger_row.quantity_change == Decimal("100.000")
    assert ledger_row.quantity_after == Decimal("100.000")

    # 4. Immutability of DONE: cannot cancel or re-validate
    reval = client.post(f"/receipts/{rcpt_id}/validate", headers=headers)
    assert reval.status_code == 400

    recancel = client.post(f"/receipts/{rcpt_id}/cancel", headers=headers)
    assert recancel.status_code == 400


def test_receipt_cancellation_and_rbac(receipts_client_and_db):
    """
    Section 16 & Section 6 RBAC:
    Cancel own transaction: STAFF = YES, MANAGER = YES
    Cancel another user's transaction: STAFF = NO (403), MANAGER = YES
    """
    client, db, mgr_tok, staff1_tok, staff2_tok, prod_id, loc_id = receipts_client_and_db
    staff1_headers = {"Authorization": f"Bearer {staff1_tok}"}
    staff2_headers = {"Authorization": f"Bearer {staff2_tok}"}
    mgr_headers = {"Authorization": f"Bearer {mgr_tok}"}

    # Staff 1 creates a receipt
    rcpt1 = client.post(
        "/receipts",
        json={"product_id": prod_id, "to_location_id": loc_id, "quantity": 25.0},
        headers=staff1_headers,
    ).json()
    r1_id = rcpt1["id"]

    # Staff 2 attempts to cancel Staff 1's receipt -> 403 Forbidden
    s2_cancel = client.post(f"/receipts/{r1_id}/cancel", headers=staff2_headers)
    assert s2_cancel.status_code == 403
    assert "only cancel their own" in s2_cancel.json()["detail"].lower()

    # Staff 1 cancels Staff 1's own receipt -> ALLOWED
    s1_cancel = client.post(f"/receipts/{r1_id}/cancel", headers=staff1_headers)
    assert s1_cancel.status_code == 200
    assert s1_cancel.json()["status"] == "canceled"

    # Staff 2 creates a receipt
    rcpt2 = client.post(
        "/receipts",
        json={"product_id": prod_id, "to_location_id": loc_id, "quantity": 40.0},
        headers=staff2_headers,
    ).json()
    r2_id = rcpt2["id"]

    # Manager cancels Staff 2's receipt -> ALLOWED
    mgr_cancel = client.post(f"/receipts/{r2_id}/cancel", headers=mgr_headers)
    assert mgr_cancel.status_code == 200
    assert mgr_cancel.json()["status"] == "canceled"
