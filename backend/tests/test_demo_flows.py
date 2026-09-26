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
from app.models.transaction import TransactionType, TransactionStatus
from app.seed import seed_demo_data


@pytest.fixture(scope="function")
def demo_test_client():
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

    yield client, db

    app.dependency_overrides.clear()


def test_section_49_demo_seed_endpoint(demo_test_client):
    """
    Section 49: DEMO DATA
    WAREHOUSE: Main Warehouse (WH)
    LOCATIONS: Rack A, Rack B, Production Floor
    CATEGORIES: Raw Materials, Finished Goods, Components
    PRODUCTS: Steel Rod, Chair, Table
    USERS: Inventory Manager, Warehouse Staff
    """
    client, db = demo_test_client

    response = client.post("/api/demo/seed")
    assert response.status_code == 200
    data = response.json()

    assert data["status"] == "success"
    assert data["warehouse"]["name"] == "Main Warehouse"
    assert data["warehouse"]["short_code"] == "WH"

    # Verify locations
    expected_locations = {"Rack A", "Rack B", "Production Floor"}
    assert set(data["locations"]) == expected_locations

    # Verify categories
    expected_categories = {"Raw Materials", "Finished Goods", "Components"}
    assert set(data["categories"]) == expected_categories

    # Verify products
    product_names = {p["name"] for p in data["products"]}
    assert product_names == {"Steel Rod", "Chair", "Table"}

    # Verify users
    user_roles = {u["role"] for u in data["users"]}
    assert user_roles == {"INVENTORY_MANAGER", "WAREHOUSE_STAFF"}

    # Verify directly in database
    wh = db.query(models.Warehouse).filter_by(short_code="WH").first()
    assert wh is not None
    assert wh.name == "Main Warehouse"

    locations = db.query(models.Location).filter_by(warehouse_id=wh.id).all()
    assert {loc.name for loc in locations} == expected_locations

    categories = db.query(models.Category).all()
    assert {cat.name for cat in categories} == expected_categories

    products = db.query(models.Product).all()
    assert {prod.name for prod in products} == {"Steel Rod", "Chair", "Table"}


def test_section_50_required_demo_flow_endpoint(demo_test_client):
    """
    Section 50: REQUIRED DEMO FLOW
    1. Login.
    2. Create Steel Rod.
    3. Receive 100 kg.
    4. Stock becomes: 100 kg
    5. Transfer 30 kg: Main Warehouse -> Production Floor
       Result: Main Warehouse = 70 kg, Production Floor = 30 kg
    6. Deliver 20 kg. Total: 80 kg
    7. Adjust -3 kg damaged. Total: 77 kg
    8. Open Move History.
    9. Open Stock Ledger.
    10. Open Inventory Intelligence.
    """
    client, db = demo_test_client

    response = client.post("/api/demo/section-50")
    assert response.status_code == 200
    data = response.json()

    assert data["status"] == "success"
    assert data["final_stock"]["Main Warehouse (Rack A)"] == 47.0
    assert data["final_stock"]["Production Floor"] == 30.0
    assert data["final_stock"]["Total"] == 77.0

    steps = {s["step"]: s for s in data["steps"]}
    assert steps[1]["action"] == "Login"
    assert steps[2]["action"] == "Create Steel Rod"
    assert steps["3-4"]["stock_rack_a"] == 100.0
    assert steps[5]["result"]["Main Warehouse (Rack A)"] == 70.0
    assert steps[5]["result"]["Production Floor"] == 30.0
    assert steps[5]["result"]["Total"] == 100.0
    assert steps[6]["result"]["Rack A"] == 50.0
    assert steps[6]["result"]["Total"] == 80.0
    assert steps[7]["result"]["Rack A"] == 47.0
    assert steps[7]["result"]["Total"] == 77.0
    assert steps[8]["action"] == "Open Move History"
    assert steps[8]["moves_count"] == 4
    assert steps[9]["action"] == "Open Stock Ledger"
    assert steps[9]["ledger_entries_count"] >= 5
    assert steps[10]["action"] == "Open Inventory Intelligence"
    assert steps[10]["current_stock"] == 77.0


def test_section_51_advanced_demo_flow_endpoint(demo_test_client):
    """
    Section 51: ADVANCED DEMO
    Demonstrate:
      Available stock = 5
      Create delivery: 20
      Result: WAITING
      Then receive: 15
      System checks waiting deliveries.
      Delivery becomes: READY
      System reserves stock.
      Validate.
      Delivery becomes: DONE
      Stock is correctly reduced.
    """
    client, db = demo_test_client

    response = client.post("/api/demo/section-51")
    assert response.status_code == 200
    data = response.json()

    assert data["status"] == "success"
    assert data["final_stock"] == 0.0

    stages = {s["stage"]: s for s in data["steps"]}
    # Stage 1: Initial stock = 5
    assert stages[1]["free_to_use"] == 5.0
    # Stage 2: Delivery 20 requested -> WAITING
    assert stages[2]["delivery_status"] == "WAITING"
    # Stage 3: Received 15 -> check waiting deliveries -> READY & stock reserved
    assert stages[3]["delivery_status"] == "READY"
    assert stages[3]["on_hand"] == 20.0
    assert stages[3]["reserved"] == 20.0
    assert stages[3]["free_to_use"] == 0.0
    # Stage 4: Validated -> DONE & stock reduced correctly
    assert stages[4]["delivery_status"] == "DONE"
    assert stages[4]["final_on_hand"] == 0.0
    assert stages[4]["final_reserved"] == 0.0
    assert stages[4]["final_free_to_use"] == 0.0


def test_section_50_interactive_rest_sequence(demo_test_client):
    """
    Execute Section 50 using individual REST endpoints sequentially.
    """
    client, db = demo_test_client

    # 0. Seed Demo Data
    seed_res = client.post("/api/demo/seed")
    assert seed_res.status_code == 200

    # 1. Login
    login_res = client.post(
        "/api/auth/login",
        json={"email": "manager@stocksense.com", "password": "password123"},
    )
    assert login_res.status_code == 200
    token = login_res.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Fetch IDs
    prod_res = client.get("/api/products", headers=headers)
    assert prod_res.status_code == 200
    steel_rod = next(p for p in prod_res.json() if p["name"] == "Steel Rod")
    prod_id = steel_rod["id"]

    loc_res = client.get("/api/locations", headers=headers)
    assert loc_res.status_code == 200
    rack_a = next(l for l in loc_res.json() if l["name"] == "Rack A")
    prod_floor = next(l for l in loc_res.json() if l["name"] == "Production Floor")

    # 3. Receive 100 kg
    rec_res = client.post(
        "/api/receipts",
        headers=headers,
        json={
            "product_id": prod_id,
            "to_location_id": rack_a["id"],
            "quantity": 100.0,
            "contact": "Steel Corp",
        },
    )
    assert rec_res.status_code == 201
    rec_id = rec_res.json()["id"]

    val_rec = client.post(f"/api/receipts/{rec_id}/validate", headers=headers)
    assert val_rec.status_code == 200
    assert val_rec.json()["status"] == "done" or val_rec.json()["status"] == "DONE"

    # 4. Stock becomes: 100 kg
    stock_res = client.get(f"/api/stock?location_id={rack_a['id']}", headers=headers)
    assert stock_res.status_code == 200
    stock_item = next(s for s in stock_res.json() if s["product_id"] == prod_id)
    assert float(stock_item["on_hand"]) == 100.0

    # 5. Transfer 30 kg: Main Warehouse (Rack A) -> Production Floor
    trf_res = client.post(
        "/api/transfers",
        headers=headers,
        json={
            "product_id": prod_id,
            "from_location_id": rack_a["id"],
            "to_location_id": prod_floor["id"],
            "quantity": 30.0,
            "contact": "Internal Transfer",
        },
    )
    assert trf_res.status_code == 201
    trf_id = trf_res.json()["id"]

    ready_trf = client.post(f"/api/transfers/{trf_id}/ready", headers=headers)
    assert ready_trf.status_code == 200

    val_trf = client.post(f"/api/transfers/{trf_id}/validate", headers=headers)
    assert val_trf.status_code == 200
    assert val_trf.json()["status"] == "done" or val_trf.json()["status"] == "DONE"

    # Result: Main Warehouse = 70 kg, Production Floor = 30 kg
    res_rack_a = client.get(f"/api/stock?location_id={rack_a['id']}", headers=headers)
    res_prod_fl = client.get(f"/api/stock?location_id={prod_floor['id']}", headers=headers)
    stock_rack_a = next(s for s in res_rack_a.json() if s["product_id"] == prod_id)
    stock_prod_fl = next(s for s in res_prod_fl.json() if s["product_id"] == prod_id)
    assert float(stock_rack_a["on_hand"]) == 70.0
    assert float(stock_prod_fl["on_hand"]) == 30.0

    # 6. Deliver 20 kg. Total: 80 kg
    del_res = client.post(
        "/api/deliveries",
        headers=headers,
        json={
            "product_id": prod_id,
            "from_location_id": rack_a["id"],
            "quantity": 20.0,
            "contact": "Customer XYZ",
        },
    )
    assert del_res.status_code == 201
    del_id = del_res.json()["id"]

    prep_del = client.post(f"/api/deliveries/{del_id}/ready", headers=headers)
    assert prep_del.status_code == 200
    assert prep_del.json()["status"] == "ready" or prep_del.json()["status"] == "READY"

    val_del = client.post(f"/api/deliveries/{del_id}/validate", headers=headers)
    assert val_del.status_code == 200
    assert val_del.json()["status"] == "done" or val_del.json()["status"] == "DONE"

    res_rack_a = client.get(f"/api/stock?location_id={rack_a['id']}", headers=headers)
    res_prod_fl = client.get(f"/api/stock?location_id={prod_floor['id']}", headers=headers)
    stock_rack_a = next(s for s in res_rack_a.json() if s["product_id"] == prod_id)
    stock_prod_fl = next(s for s in res_prod_fl.json() if s["product_id"] == prod_id)
    assert float(stock_rack_a["on_hand"]) == 50.0
    assert float(stock_prod_fl["on_hand"]) == 30.0
    assert float(stock_rack_a["on_hand"]) + float(stock_prod_fl["on_hand"]) == 80.0

    # 7. Adjust -3 kg damaged. Total: 77 kg
    # Current on-hand at Rack A is 50. Physical count is 47. Difference = -3.
    adj_res = client.post(
        "/api/adjustments",
        headers=headers,
        json={
            "location_id": rack_a["id"],
            "product_id": prod_id,
            "physical_count": 47.0,
            "reason": "Damaged",
        },
    )
    assert adj_res.status_code == 201
    adj_id = adj_res.json()["id"]

    val_adj = client.post(f"/api/adjustments/{adj_id}/validate", headers=headers)
    assert val_adj.status_code == 200
    assert val_adj.json()["status"] == "done" or val_adj.json()["status"] == "DONE"

    res_rack_a = client.get(f"/api/stock?location_id={rack_a['id']}", headers=headers)
    res_prod_fl = client.get(f"/api/stock?location_id={prod_floor['id']}", headers=headers)
    stock_rack_a = next(s for s in res_rack_a.json() if s["product_id"] == prod_id)
    stock_prod_fl = next(s for s in res_prod_fl.json() if s["product_id"] == prod_id)
    assert float(stock_rack_a["on_hand"]) == 47.0
    assert float(stock_prod_fl["on_hand"]) == 30.0
    total_stock = float(stock_rack_a["on_hand"]) + float(stock_prod_fl["on_hand"])
    assert total_stock == 77.0

    # 8. Open Move History
    moves_res = client.get("/api/moves", headers=headers)
    assert moves_res.status_code == 200
    moves = moves_res.json()
    assert len(moves) >= 4

    # 9. Open Stock Ledger
    ledger_res = client.get(f"/api/stock-ledger?product_id={prod_id}", headers=headers)
    assert ledger_res.status_code == 200
    ledger = ledger_res.json()
    assert len(ledger) >= 5

    # 10. Open Inventory Intelligence
    stockout_res = client.get("/api/intelligence/stockout", headers=headers)
    assert stockout_res.status_code == 200
    stockout_data = stockout_res.json()
    steel_rod_intel = next(item for item in stockout_data if item["product_id"] == prod_id)
    assert float(steel_rod_intel["current_stock"]) == 77.0
