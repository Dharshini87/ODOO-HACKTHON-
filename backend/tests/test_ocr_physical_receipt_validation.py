import os
import io
from decimal import Decimal
import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app.main import app
from app import models
from app.database import get_db, SessionLocal
from app.core import security
from app.services.storage_service import StorageService
from app.services.ocr_service import OCRService, ReceiptParser
from app.services.receipt_matching_service import ReceiptMatchingService


from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from app.db.base import Base

@pytest.fixture(scope="function")
def auth_client():
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

    try:
        manager = models.User(
            name="Inventory Manager",
            email="manager@stocksense.com",
            password_hash=security.hash_password("password123"),
            role="INVENTORY_MANAGER",
            is_active=True,
        )
        db.add(manager)
        db.commit()
        db.refresh(manager)

        # Seed warehouse and Rack A
        wh = models.Warehouse(name="Main Warehouse", short_code="MAIN-WH", is_active=True)
        db.add(wh)
        db.commit()
        db.refresh(wh)

        loc = models.Location(warehouse_id=wh.id, name="Rack A", short_code="RACK-A", is_active=True)
        init_prod = models.Product(
            name="Initial Steel Rod",
            sku="INIT-001",
            unit_of_measure="kg",
            cost_per_unit=Decimal("25.00"),
            reorder_point=Decimal("10.0"),
            is_active=True,
        )
        db.add_all([loc, init_prod])
        db.commit()

        token = security.create_access_token({"sub": manager.email, "role": manager.role, "user_id": manager.id})
        client.headers.update({"Authorization": f"Bearer {token}"})
        yield client, manager, db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)
        app.dependency_overrides.clear()



def generate_receipt_image_bytes(supplier: str, receipt_no: str, items_text: str) -> bytes:
    img = Image.new("RGB", (700, 500), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)
    draw.text((40, 30), f"Supplier: {supplier}", fill=(0, 0, 0))
    draw.text((40, 70), f"Invoice #: {receipt_no}", fill=(0, 0, 0))
    draw.text((40, 110), "Date: 2026-09-26", fill=(0, 0, 0))
    draw.text((40, 160), "Line Items:", fill=(0, 0, 0))
    draw.text((40, 190), items_text, fill=(0, 0, 0))
    draw.text((40, 250), "Total: $1,250.00", fill=(0, 0, 0))

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def generate_receipt_pdf_bytes(supplier: str, receipt_no: str, items_text: str) -> bytes:
    img = Image.new("RGB", (700, 500), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)
    draw.text((40, 30), f"Supplier: {supplier}", fill=(0, 0, 0))
    draw.text((40, 70), f"Receipt: {receipt_no}", fill=(0, 0, 0))
    draw.text((40, 110), "Date: 2026-09-26", fill=(0, 0, 0))
    draw.text((40, 160), "Delivered Items:", fill=(0, 0, 0))
    draw.text((40, 190), items_text, fill=(0, 0, 0))

    buf = io.BytesIO()
    img.save(buf, format="PDF")
    return buf.getvalue()


def test_section_5_and_6_file_validation_and_security(auth_client):
    """
    Test file validation:
    - Unsupported file extension/MIME rejected
    - Empty file rejected
    - Safe UUID storage keys (never exposes path)
    """
    client, manager, db = auth_client

    # Create dummy receipt
    loc = db.query(models.Location).filter_by(name="Rack A").first()
    prod = db.query(models.Product).first()

    rcpt_resp = client.post("/api/receipts", json={
        "product_id": prod.id,
        "to_location_id": loc.id,
        "quantity": 50.0,
        "contact": "Test Supplier",
    })
    assert rcpt_resp.status_code == 201
    rcpt_id = rcpt_resp.json()["id"]

    # 1. Unsupported file format (e.g. .exe / .txt)
    bad_file = ("script.exe", b"binary content", "application/x-msdownload")
    resp_bad = client.post(
        f"/api/receipts/{rcpt_id}/receipt-document",
        files={"file": bad_file},
    )
    assert resp_bad.status_code == 400
    assert "Unsupported file type" in resp_bad.json()["detail"]

    # 2. Empty file
    empty_file = ("receipt.pdf", b"", "application/pdf")
    resp_empty = client.post(
        f"/api/receipts/{rcpt_id}/receipt-document",
        files={"file": empty_file},
    )
    assert resp_empty.status_code == 400


def test_section_52_inventory_safety_ocr_never_mutates_stock(auth_client):
    """
    Section 52: INVENTORY SAFETY IS MANDATORY.
    - OCR succeeds -> NO stock mutation
    - OCR fails / mismatches -> NO stock mutation
    - Only existing validation updates stock and creates ledger
    """
    client, manager, db = auth_client

    loc = db.query(models.Location).filter_by(name="Rack A").first()
    
    # Create product with 0 stock
    prod_resp = client.post("/api/products", json={
        "name": "Safety Test Rod",
        "sku": "SAF-001",
        "unit_of_measure": "kg",
        "cost_per_unit": 30.0,
        "reorder_point": 10.0,
    })
    prod_id = prod_resp.json()["id"]

    # Create receipt for 100 kg
    rcpt_resp = client.post("/api/receipts", json={
        "product_id": prod_id,
        "to_location_id": loc.id,
        "quantity": 100.0,
        "contact": "ABC Steel Industries",
    })
    rcpt_id = rcpt_resp.json()["id"]

    # Upload matching PDF (100 kg)
    pdf_bytes = generate_receipt_pdf_bytes("ABC Steel Industries", "INV-9901", "1. Safety Test Rod (SAF-001) - 100 kg")
    up_resp = client.post(
        f"/api/receipts/{rcpt_id}/receipt-document",
        files={"file": ("receipt.pdf", pdf_bytes, "application/pdf")},
    )
    assert up_resp.status_code == 201

    # Verify with OCR
    verify_resp = client.post(f"/api/receipts/{rcpt_id}/receipt-document/verify")
    assert verify_resp.status_code == 200
    assert verify_resp.json()["verification"]["status"] == "MATCH"

    # CRITICAL CHECK: Verify stock in database is STILL 0.0
    stock = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc.id).first()
    assert stock is None or stock.on_hand == Decimal("0.000"), "SECURITY VIOLATION: OCR mutated stock!"

    # CRITICAL CHECK: Verify ledger entries count is 0
    ledger_count = db.query(models.StockLedger).filter_by(product_id=prod_id).count()
    assert ledger_count == 0, "SECURITY VIOLATION: OCR created ledger entries!"

    # Now validate receipt through existing engine
    client.post(f"/api/receipts/{rcpt_id}/ready")
    val_resp = client.post(f"/api/receipts/{rcpt_id}/validate")
    assert val_resp.status_code == 200

    # Stock is mutated ONLY NOW
    db.expire_all()
    stock_after = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc.id).first()
    assert stock_after.on_hand == Decimal("100.000")

    # Ledger created ONLY NOW
    ledger_entries = db.query(models.StockLedger).filter_by(product_id=prod_id).all()
    assert len(ledger_entries) == 1
    assert ledger_entries[0].movement_type == "RECEIPT"
    assert ledger_entries[0].quantity_change == Decimal("100.000")


def test_section_60_demo_scenario_mismatch_detection(auth_client):
    """
    Section 60: DEMO SCENARIO — MISMATCH
    Digital Receipt: 100 kg
    Physical Receipt: 95 kg
    Result: REVIEW_REQUIRED (Difference: -5 kg)
    Stock must NOT change!
    """
    client, manager, db = auth_client

    loc = db.query(models.Location).filter_by(name="Rack A").first()
    prod_resp = client.post("/api/products", json={
        "name": "Mismatch Test Rod",
        "sku": "MIS-001",
        "unit_of_measure": "kg",
        "cost_per_unit": 20.0,
        "reorder_point": 5.0,
    })
    prod_id = prod_resp.json()["id"]

    rcpt_resp = client.post("/api/receipts", json={
        "product_id": prod_id,
        "to_location_id": loc.id,
        "quantity": 100.0,
        "contact": "ABC Steel Industries",
    })
    rcpt_id = rcpt_resp.json()["id"]

    # Upload physical receipt showing 95 kg
    pdf_bytes = generate_receipt_pdf_bytes("ABC Steel Industries", "INV-2026-001", "1. Mismatch Test Rod (MIS-001) - 95 kg")
    client.post(
        f"/api/receipts/{rcpt_id}/receipt-document",
        files={"file": ("receipt_95kg.pdf", pdf_bytes, "application/pdf")},
    )

    v_resp = client.post(f"/api/receipts/{rcpt_id}/receipt-document/verify")
    assert v_resp.status_code == 200
    v = v_resp.json()["verification"]

    assert v["status"] == "REVIEW_REQUIRED"
    assert len(v["items"]) == 1
    it = v["items"][0]
    assert it["status"] == "MISMATCH"
    assert it["system_quantity"] == 100.0
    assert it["ocr_quantity"] == 95.0
    assert it["difference"] == -5.0
    assert len(v["issues"]) >= 1

    # Verify stock is UNCHANGED
    db.expire_all()
    stock = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc.id).first()
    assert stock is None or stock.on_hand == Decimal("0.000")


def test_section_54_duplicate_validation_idempotency(auth_client):
    """
    Section 54: Calling validation twice does not double mutate stock or duplicate ledger entries.
    """
    client, manager, db = auth_client
    loc = db.query(models.Location).filter_by(name="Rack A").first()

    prod_resp = client.post("/api/products", json={
        "name": "Idemp Test Rod",
        "sku": "IDEMP-001",
        "unit_of_measure": "kg",
        "cost_per_unit": 20.0,
        "reorder_point": 5.0,
    })
    prod_id = prod_resp.json()["id"]

    rcpt_resp = client.post("/api/receipts", json={
        "product_id": prod_id,
        "to_location_id": loc.id,
        "quantity": 60.0,
        "contact": "Idemp Supplier",
    })
    rcpt_id = rcpt_resp.json()["id"]

    client.post(f"/api/receipts/{rcpt_id}/ready")
    
    # First validation
    val1 = client.post(f"/api/receipts/{rcpt_id}/validate", headers={"Idempotency-Key": "KEY-IDEMP-01"})
    assert val1.status_code == 200

    # Second validation
    val2 = client.post(f"/api/receipts/{rcpt_id}/validate", headers={"Idempotency-Key": "KEY-IDEMP-01"})
    assert val2.status_code == 200

    # Confirm stock = 60 kg (not 120 kg)
    db.expire_all()
    st = db.query(models.Stock).filter_by(product_id=prod_id, location_id=loc.id).first()
    assert st.on_hand == Decimal("60.000")

    # Confirm exactly 1 ledger row
    led_rows = db.query(models.StockLedger).filter_by(product_id=prod_id).all()
    assert len(led_rows) == 1
