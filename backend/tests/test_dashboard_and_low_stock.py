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

    # Create Manager User
    manager = models.User(
        name="Dashboard Manager",
        email="dash_manager@example.com",
        password_hash=security.hash_password("Secret123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    db.add(manager)
    db.commit()
    db.refresh(manager)

    # Create Warehouse & Location
    wh = models.Warehouse(name="Central Warehouse", short_code="CWH", address="100 Logistics Way")
    db.add(wh)
    db.commit()
    db.refresh(wh)

    loc1 = models.Location(warehouse_id=wh.id, name="Rack A1", short_code="RA1")
    loc2 = models.Location(warehouse_id=wh.id, name="Rack B2", short_code="RB2")
    db.add_all([loc1, loc2])
    db.commit()
    db.refresh(loc1)
    db.refresh(loc2)

    # Create 3 Products to test Section 27 rules:
    # Product 1: Out of Stock (on_hand == 0)
    p_out = models.Product(
        name="Steel Bearings",
        sku="BEAR-001",
        unit_of_measure="pcs",
        cost_per_unit=Decimal("15.50"),
        reorder_point=Decimal("20.000"),
        is_active=True,
    )
    # Product 2: Low Stock (on_hand <= reorder_level)
    p_low = models.Product(
        name="Copper Wire",
        sku="WIRE-002",
        unit_of_measure="m",
        cost_per_unit=Decimal("5.00"),
        reorder_point=Decimal("50.000"),
        is_active=True,
    )
    # Product 3: Normal Stock (on_hand > reorder_level)
    p_norm = models.Product(
        name="Industrial Bolts",
        sku="BOLT-003",
        unit_of_measure="box",
        cost_per_unit=Decimal("8.25"),
        reorder_point=Decimal("30.000"),
        is_active=True,
    )
    db.add_all([p_out, p_low, p_norm])
    db.commit()
    db.refresh(p_out)
    db.refresh(p_low)
    db.refresh(p_norm)

    # Assign initial stocks:
    # p_out: no stock row -> on_hand = 0
    # p_low: on_hand = 35, reserved = 10 -> free_to_use = 25 (35 <= reorder_point 50 -> LOW STOCK)
    s_low = models.Stock(
        product_id=p_low.id,
        location_id=loc1.id,
        on_hand=Decimal("35.000"),
        reserved=Decimal("10.000"),
    )
    # p_norm: on_hand = 100, reserved = 20 -> free_to_use = 80 (100 > reorder_point 30 -> NORMAL)
    s_norm = models.Stock(
        product_id=p_norm.id,
        location_id=loc2.id,
        on_hand=Decimal("100.000"),
        reserved=Decimal("20.000"),
    )
    db.add_all([s_low, s_norm])
    db.commit()

    token = security.create_access_token({
        "sub": manager.email,
        "email": manager.email,
        "role": manager.role,
        "user_id": manager.id,
    })
    headers = {"Authorization": f"Bearer {token}"}

    yield client, db, headers, {
        "manager": manager,
        "wh": wh,
        "loc1": loc1,
        "loc2": loc2,
        "p_out": p_out,
        "p_low": p_low,
        "p_norm": p_norm,
    }
    db.close()
    app.dependency_overrides.clear()


def test_section_26_dashboard_summary_endpoint(client_and_db):
    client, db, headers, fixtures = client_and_db

    # Call GET /api/dashboard/summary
    res = client.get("/api/dashboard/summary", headers=headers)
    assert res.status_code == 200, res.text
    data = res.json()

    # Section 26 Display Metrics:
    # Total stock: 0 + 35 + 100 = 135
    assert data["total_stock"] == 135.0
    # Out of stock: p_out has on_hand == 0 -> 1
    assert data["out_of_stock"] == 1
    # Low stock: p_low has 0 < 35 <= 50 -> 1
    assert data["low_stock"] == 1
    # Pending receipts, deliveries, transfers
    assert data["pending_receipts"] == 0
    assert data["pending_deliveries"] == 0
    assert data["waiting_deliveries"] == 0
    assert data["transfers_scheduled"] == 0


def test_section_27_low_stock_rules_and_display_quantities(client_and_db):
    client, db, headers, fixtures = client_and_db

    res = client.get("/api/dashboard/summary", headers=headers)
    assert res.status_code == 200
    data = res.json()

    low_stock_products = data["low_stock_products"]
    # Should include p_out (OUT OF STOCK) and p_low (LOW STOCK)
    assert len(low_stock_products) == 2

    # Check p_out
    out_item = next(it for it in low_stock_products if it["sku"] == "BEAR-001")
    assert out_item["on_hand"] == 0.0
    assert out_item["reserved"] == 0.0
    assert out_item["free_to_use"] == 0.0
    assert out_item["reorder_level"] == 20.0
    assert out_item["status"] == "OUT OF STOCK"

    # Check p_low
    low_item = next(it for it in low_stock_products if it["sku"] == "WIRE-002")
    assert low_item["on_hand"] == 35.0
    assert low_item["reserved"] == 10.0
    assert low_item["free_to_use"] == 25.0
    assert low_item["reorder_level"] == 50.0
    assert low_item["status"] == "LOW STOCK"

    # Ensure normal product is not in low stock list
    assert all(it["sku"] != "BOLT-003" for it in low_stock_products)


def test_section_26_waiting_deliveries_and_scheduled_operations(client_and_db):
    client, db, headers, fixtures = client_and_db

    # Create a draft receipt
    tx_rec = models.Transaction(
        reference="WH/IN/0001",
        type=models.TransactionType.RECEIPT,
        status=models.TransactionStatus.DRAFT,
        destination_location_id=fixtures["loc1"].id,
    )
    # Create a WAITING delivery (Section 26 explicitly highlights Waiting Deliveries)
    tx_del = models.Transaction(
        reference="WH/OUT/0001",
        type=models.TransactionType.DELIVERY,
        status=models.TransactionStatus.WAITING,
        source_location_id=fixtures["loc1"].id,
    )
    # Create a scheduled transfer in READY status
    tx_tr = models.Transaction(
        reference="WH/TR/0001",
        type=models.TransactionType.TRANSFER,
        status=models.TransactionStatus.READY,
        source_location_id=fixtures["loc1"].id,
        destination_location_id=fixtures["loc2"].id,
    )
    db.add_all([tx_rec, tx_del, tx_tr])
    db.commit()

    res = client.get("/api/dashboard/summary", headers=headers)
    assert res.status_code == 200
    data = res.json()

    assert data["pending_receipts"] == 1
    assert data["pending_deliveries"] == 1
    assert data["waiting_deliveries"] == 1
    assert data["transfers_scheduled"] == 1

    # Check recent movements list
    assert len(data["recent_movements"]) >= 3
    refs = [m["reference"] for m in data["recent_movements"]]
    assert "WH/IN/0001" in refs
    assert "WH/OUT/0001" in refs
    assert "WH/TR/0001" in refs
