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
def ledger_client_and_db():
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

    # Create Manager User
    manager = models.User(
        name="Sarah Manager",
        email="manager@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    db.add(manager)
    db.commit()
    db.refresh(manager)

    # Warehouse & Location
    wh = models.Warehouse(name="Main Warehouse", short_code="WH-M")
    db.add(wh)
    db.commit()
    db.refresh(wh)

    loc = models.Location(warehouse_id=wh.id, name="Rack A", short_code="RACK-A")
    db.add(loc)
    db.commit()
    db.refresh(loc)

    # Product
    prod = models.Product(
        name="Steel Rod",
        sku="SR-001",
        unit_of_measure="kg",
        cost_per_unit=Decimal("45.00"),
        reorder_point=Decimal("15.000"),
        is_active=True,
    )
    db.add(prod)
    db.commit()
    db.refresh(prod)

    token = security.create_access_token({
        "sub": manager.email,
        "email": manager.email,
        "role": manager.role,
        "user_id": manager.id,
    })

    yield client, db, manager, wh, loc, prod, token

    app.dependency_overrides.clear()


def test_section_24_stock_ledger_fields_and_immutability(ledger_client_and_db):
    """
    Section 24: STOCK LEDGER
    Verify fields:
      - id, transaction_id, product_id, location_id
      - quantity_before, quantity_change, quantity_after
      - movement_type (RECEIPT, DELIVERY, TRANSFER_IN, TRANSFER_OUT, ADJUSTMENT)
      - created_at
    Ledger is: READ ONLY, APPEND ONLY, IMMUTABLE.
    """
    client, db, manager, wh, loc, prod, token = ledger_client_and_db
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Query the ledger endpoint
    res = client.get("/api/ledger", headers=headers)
    assert res.status_code == 200
    entries = res.json()
    assert isinstance(entries, list)

    # 2. Verify immutability: POST / PUT / DELETE should NOT be allowed (405 Method Not Allowed)
    post_res = client.post("/api/ledger", json={"fake": "data"}, headers=headers)
    assert post_res.status_code in (404, 405)

    delete_res = client.delete("/api/ledger/1", headers=headers)
    assert delete_res.status_code in (404, 405)

    # 3. Create and validate a receipt to observe explicit ledger fields
    engine = InventoryTransactionEngine(db)

    tx = models.Transaction(
        reference="WH/IN/LEDGER-001",
        type=TransactionType.RECEIPT,
        status=TransactionStatus.DRAFT,
        destination_location_id=loc.id,
        contact="Vendor Ledger Test",
        created_by=manager.id,
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)

    item = models.TransactionItem(
        transaction_id=tx.id,
        product_id=prod.id,
        quantity=Decimal("50.000"),
    )
    db.add(item)
    db.commit()

    # Validate transaction
    engine.validate_transaction(tx.id, manager)

    # Query ledger for this transaction
    ledger_res = client.get(f"/api/ledger?transaction_id={tx.id}", headers=headers)
    assert ledger_res.status_code == 200
    ledger_data = ledger_res.json()
    assert len(ledger_data) == 1

    entry = ledger_data[0]
    assert entry["transaction_id"] == tx.id
    assert entry["product_id"] == prod.id
    assert entry["location_id"] == loc.id
    assert entry["movement_type"] == "RECEIPT"
    assert entry["quantity_before"] == pytest.approx(0.0, 0.001)
    assert entry["quantity_change"] == pytest.approx(50.0, 0.001)
    assert entry["quantity_after"] == pytest.approx(50.0, 0.001)
    assert entry["created_at"] is not None


def test_section_25_moves_derived_from_transactions_and_ledger(ledger_client_and_db):
    """
    Section 25: MOVE HISTORY
    Rule: Do NOT create a separate move history table.
    Derive data from: transactions, transaction_items, stock_ledger
    Mobile display: Reference, Date, Contact, From, To, Quantity, Status
    Search: Reference, Contact, SKU
    Filters: Type, Status, Product, Warehouse, Location, Date
    """
    client, db, manager, wh, loc, prod, token = ledger_client_and_db
    headers = {"Authorization": f"Bearer {token}"}

    engine = InventoryTransactionEngine(db)

    # Create and validate a receipt
    tx = models.Transaction(
        reference="WH/IN/DERIVE-001",
        type=TransactionType.RECEIPT,
        status=TransactionStatus.DRAFT,
        destination_location_id=loc.id,
        contact="Vendor A",
        created_by=manager.id,
    )
    db.add(tx)
    db.commit()
    db.refresh(tx)

    item = models.TransactionItem(
        transaction_id=tx.id,
        product_id=prod.id,
        quantity=Decimal("30.000"),
    )
    db.add(item)
    db.commit()

    engine.validate_transaction(tx.id, manager)

    # Query /api/moves
    res = client.get("/api/moves", headers=headers)
    assert res.status_code == 200
    moves = res.json()
    assert len(moves) >= 1

    m = moves[0]
    # Verify required mobile display fields
    assert "reference" in m
    assert "date" in m
    assert "contact" in m
    assert "from_location" in m
    assert "to_location" in m
    assert "quantity" in m
    assert "status" in m
    assert "product_name" in m
    assert "sku" in m
    assert "type" in m
    assert "ledger_entries" in m

    # Test Search by Reference
    search_ref = client.get("/api/moves?search=DERIVE-001", headers=headers)
    assert search_ref.status_code == 200
    assert len(search_ref.json()) >= 1
    assert search_ref.json()[0]["reference"] == "WH/IN/DERIVE-001"

    # Test Search by SKU
    search_sku = client.get(f"/api/moves?search={prod.sku}", headers=headers)
    assert search_sku.status_code == 200
    assert len(search_sku.json()) >= 1

    # Test Search by Contact
    search_contact = client.get("/api/moves?search=Vendor A", headers=headers)
    assert search_contact.status_code == 200
    assert len(search_contact.json()) >= 1

    # Test Filter by Type and Status
    filter_res = client.get("/api/moves?type=RECEIPT&status=DONE", headers=headers)
    assert filter_res.status_code == 200
    for item in filter_res.json():
        assert item["type"] == "RECEIPT"
        assert item["status"] == "DONE"

    # Test Pagination (skip and limit)
    page_res = client.get("/api/moves?skip=0&limit=1", headers=headers)
    assert page_res.status_code == 200
    assert len(page_res.json()) == 1
