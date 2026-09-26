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


@pytest.fixture(scope="function")
def intel_client_and_db():
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
        name="Intel Manager",
        email="intel_manager@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    db.add(manager)
    db.commit()
    db.refresh(manager)

    # Warehouse & Location
    wh = models.Warehouse(name="Logistics Center", short_code="LC")
    db.add(wh)
    db.commit()
    db.refresh(wh)

    loc = models.Location(warehouse_id=wh.id, name="Main Storage", short_code="MS")
    db.add(loc)
    db.commit()
    db.refresh(loc)

    # Product 1: Insufficient history (brand new product, 0 movements)
    p_new = models.Product(
        name="Titanium Fasteners",
        sku="TIT-001",
        unit_of_measure="pcs",
        cost_per_unit=Decimal("45.00"),
        reorder_point=Decimal("20.000"),
        is_active=True,
    )

    # Product 2: Active product with outbound history
    p_active = models.Product(
        name="Steel Beams",
        sku="STL-002",
        unit_of_measure="pcs",
        cost_per_unit=Decimal("120.00"),
        reorder_point=Decimal("20.000"),
        is_active=True,
    )

    db.add_all([p_new, p_active])
    db.commit()
    db.refresh(p_new)
    db.refresh(p_active)

    # Stock levels
    s_new = models.Stock(product_id=p_new.id, location_id=loc.id, on_hand=Decimal("50.000"), reserved=Decimal("0.0"))
    s_active = models.Stock(product_id=p_active.id, location_id=loc.id, on_hand=Decimal("80.000"), reserved=Decimal("0.0"))
    db.add_all([s_new, s_active])
    db.commit()

    # Seed outbound movement for p_active:
    # 2 days ago: Delivery of 20 units (DONE)
    two_days_ago = datetime.datetime.utcnow() - datetime.timedelta(days=2)
    tx_del = models.Transaction(
        reference="WH/OUT/0010",
        type=models.TransactionType.DELIVERY,
        status=models.TransactionStatus.DONE,
        source_location_id=loc.id,
        created_at=two_days_ago,
    )
    db.add(tx_del)
    db.commit()
    db.refresh(tx_del)

    item = models.TransactionItem(
        transaction_id=tx_del.id,
        product_id=p_active.id,
        quantity=Decimal("40.000"),
    )
    db.add(item)
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
        "p_new": p_new,
        "p_active": p_active,
        "loc": loc,
    }

    db.close()
    app.dependency_overrides.clear()


def test_section_28_stockout_insufficient_history(intel_client_and_db):
    client, db, headers, fixtures = intel_client_and_db
    p_new = fixtures["p_new"]

    # Call GET /api/intelligence/stockout for product with 0 movements
    res = client.get(f"/api/intelligence/stockout?product_id={p_new.id}", headers=headers)
    assert res.status_code == 200, res.text
    data = res.json()

    assert len(data) == 1
    item = data[0]
    assert item["sku"] == "TIT-001"
    assert item["current_stock"] == 50.0
    assert item["reorder_level"] == 20.0
    # Section 28 exact requirement: show "Not enough historical movement data."
    assert item["has_sufficient_history"] is False
    assert item["message"] == "Not enough historical movement data."
    # Must not fabricate predictions
    assert item["average_daily_usage"] is None
    assert item["estimated_days_to_stockout"] is None
    assert item["estimated_days_to_reorder"] is None


def test_section_28_stockout_transparent_calculations(intel_client_and_db):
    client, db, headers, fixtures = intel_client_and_db
    p_active = fixtures["p_active"]

    res = client.get(f"/api/intelligence/stockout?product_id={p_active.id}", headers=headers)
    assert res.status_code == 200, res.text
    data = res.json()

    assert len(data) == 1
    item = data[0]
    assert item["sku"] == "STL-002"
    assert item["current_stock"] == 80.0
    assert item["has_sufficient_history"] is True
    assert item["message"] is None

    # Total 40 units across ~2 days => ~20 units/day
    avg_usage = item["average_daily_usage"]
    assert avg_usage > 0
    # Estimated days to stockout: 80 / avg_usage
    expected_days_stockout = round(80.0 / avg_usage, 1)
    assert item["estimated_days_to_stockout"] == expected_days_stockout

    # Estimated days to reorder: (80 - 20) / avg_usage
    expected_days_reorder = round((80.0 - 20.0) / avg_usage, 1)
    assert item["estimated_days_to_reorder"] == expected_days_reorder


def test_section_28_reorder_recommendation_and_explanation(intel_client_and_db):
    client, db, headers, fixtures = intel_client_and_db
    p_active = fixtures["p_active"]

    # Target coverage = 10 days
    res = client.get(f"/api/intelligence/reorder?product_id={p_active.id}&target_coverage=10", headers=headers)
    assert res.status_code == 200, res.text
    data = res.json()

    assert len(data) == 1
    item = data[0]
    assert item["sku"] == "STL-002"
    assert item["current_stock"] == 80.0
    assert item["target_coverage"] == 10
    assert item["has_sufficient_history"] is True

    # Check that explanation formula is transparent and returned to user
    explanation = item["explanation"]
    assert "Formula:" in explanation or "Target Need" in explanation
    assert "Current Stock" in explanation
    assert item["recommended_reorder_quantity"] >= 0.0
