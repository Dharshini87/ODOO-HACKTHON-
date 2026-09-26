from decimal import Decimal
import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from .. import models, auth
from ..models.transaction import TransactionType, TransactionStatus
from ..services.inventory_engine import InventoryTransactionEngine
from ..seed import seed_demo_data

router = APIRouter(tags=["Demo Flows"])


# ============================================================
# 49. SEED DEMO DATA ENDPOINT
# ============================================================
@router.post("/demo/seed")
def api_seed_demo_data(db: Session = Depends(get_db)):
    """
    Section 49: DEMO DATA
    Seeds:
      - WAREHOUSE: Main Warehouse (WH)
      - LOCATIONS: Rack A, Rack B, Production Floor
      - CATEGORIES: Raw Materials, Finished Goods, Components
      - PRODUCTS: Steel Rod, Chair, Table
      - USERS: Inventory Manager, Warehouse Staff
    """
    data = seed_demo_data(db)
    return {
        "status": "success",
        "message": "Section 49 demo data successfully seeded",
        "warehouse": {"name": data["warehouse"].name, "short_code": data["warehouse"].short_code},
        "locations": list(data["locations"].keys()),
        "categories": list(data["categories"].keys()),
        "products": [
            {"name": p.name, "sku": p.sku, "unit": p.unit_of_measure}
            for p in data["products"].values()
        ],
        "users": [
            {"role": "INVENTORY_MANAGER", "email": "manager@stocksense.com", "password": "password123"},
            {"role": "WAREHOUSE_STAFF", "email": "staff@stocksense.com", "password": "password123"},
        ],
    }


# ============================================================
# 50. REQUIRED DEMO FLOW EXECUTION
# ============================================================
@router.post("/demo/section-50")
def run_section_50_demo_flow(db: Session = Depends(get_db)):
    """
    Section 50: REQUIRED DEMO FLOW
    1. Login.
    2. Create Steel Rod.
    3. Receive 100 kg.
    4. Stock becomes: 100 kg.
    5. Transfer 30 kg: Main Warehouse -> Production Floor.
       Result: Main Warehouse = 70 kg, Production Floor = 30 kg.
    6. Deliver 20 kg. Total: 80 kg.
    7. Adjust -3 kg damaged. Total: 77 kg.
    8. Open Move History.
    9. Open Stock Ledger.
    10. Open Inventory Intelligence.
    """
    engine = InventoryTransactionEngine(db)
    seed = seed_demo_data(db)
    manager = seed["users"]["manager"]
    prod = seed["products"]["Steel Rod"]
    rack_a = seed["locations"]["Rack A"]
    prod_floor = seed["locations"]["Production Floor"]

    steps = []

    # 1. Login (Verified manager user)
    token = auth.create_access_token({"sub": manager.email, "role": manager.role})
    steps.append({"step": 1, "action": "Login", "user": manager.email, "role": manager.role, "token_generated": bool(token)})

    # 2. Create / Ensure Steel Rod
    steps.append({"step": 2, "action": "Create Steel Rod", "product": prod.name, "sku": prod.sku, "uom": prod.unit_of_measure})

    # Clear previous stock for clean flow test
    for loc_id in [rack_a.id, prod_floor.id]:
        st = db.query(models.Stock).filter_by(product_id=prod.id, location_id=loc_id).first()
        if st:
            st.on_hand = Decimal("0.000")
            st.reserved = Decimal("0.000")
    db.commit()

    # 3. Receive 100 kg
    rec_tx = models.Transaction(
        reference="REC-DEMO-S50",
        type=TransactionType.RECEIPT,
        status=TransactionStatus.READY,
        destination_location_id=rack_a.id,
        contact="Steel Supplier Corp",
        created_by=manager.id,
    )
    db.add(rec_tx)
    db.flush()
    db.add(models.TransactionItem(
        transaction_id=rec_tx.id,
        product_id=prod.id,
        quantity=Decimal("100.000"),
    ))
    db.commit()

    engine.validate_transaction(rec_tx.id, manager)

    # 4. Stock becomes: 100 kg
    stock_rack_a = db.query(models.Stock).filter_by(product_id=prod.id, location_id=rack_a.id).first()
    stock_total_after_rec = stock_rack_a.on_hand
    assert stock_total_after_rec == Decimal("100.000")
    steps.append({"step": "3-4", "action": "Receive 100 kg", "stock_rack_a": float(stock_rack_a.on_hand), "total_stock": float(stock_total_after_rec)})

    # 5. Transfer 30 kg: Main Warehouse (Rack A) -> Production Floor
    trf_tx = models.Transaction(
        reference="TRF-DEMO-S50",
        type=TransactionType.TRANSFER,
        status=TransactionStatus.READY,
        source_location_id=rack_a.id,
        destination_location_id=prod_floor.id,
        contact="Internal Logistics",
        created_by=manager.id,
    )
    db.add(trf_tx)
    db.flush()
    db.add(models.TransactionItem(
        transaction_id=trf_tx.id,
        product_id=prod.id,
        quantity=Decimal("30.000"),
    ))
    db.commit()

    engine.validate_transaction(trf_tx.id, manager)

    db.refresh(stock_rack_a)
    stock_prod_floor = db.query(models.Stock).filter_by(product_id=prod.id, location_id=prod_floor.id).first()
    assert stock_rack_a.on_hand == Decimal("70.000")
    assert stock_prod_floor.on_hand == Decimal("30.000")
    steps.append({
        "step": 5,
        "action": "Transfer 30 kg",
        "result": {
            "Main Warehouse (Rack A)": float(stock_rack_a.on_hand),
            "Production Floor": float(stock_prod_floor.on_hand),
            "Total": float(stock_rack_a.on_hand + stock_prod_floor.on_hand),
        },
    })

    # 6. Deliver 20 kg. Total: 80 kg
    del_tx = models.Transaction(
        reference="DEL-DEMO-S50",
        type=TransactionType.DELIVERY,
        status=TransactionStatus.DRAFT,
        source_location_id=rack_a.id,
        contact="Acme Engineering",
        created_by=manager.id,
    )
    db.add(del_tx)
    db.flush()
    db.add(models.TransactionItem(
        transaction_id=del_tx.id,
        product_id=prod.id,
        quantity=Decimal("20.000"),
    ))
    db.commit()

    # Prepare -> READY
    engine.prepare_delivery(del_tx.id, manager)
    # Validate -> DONE
    engine.validate_transaction(del_tx.id, manager)

    db.refresh(stock_rack_a)
    db.refresh(stock_prod_floor)
    total_stock_after_del = stock_rack_a.on_hand + stock_prod_floor.on_hand
    assert stock_rack_a.on_hand == Decimal("50.000")
    assert stock_prod_floor.on_hand == Decimal("30.000")
    assert total_stock_after_del == Decimal("80.000")
    steps.append({
        "step": 6,
        "action": "Deliver 20 kg",
        "result": {
            "Rack A": float(stock_rack_a.on_hand),
            "Production Floor": float(stock_prod_floor.on_hand),
            "Total": float(total_stock_after_del),
        },
    })

    # 7. Adjust -3 kg damaged. Total: 77 kg
    adj_tx = models.Transaction(
        reference="ADJ-DEMO-S50",
        type=TransactionType.ADJUSTMENT,
        status=TransactionStatus.DRAFT,
        source_location_id=rack_a.id,
        contact="Damage Inspection",
        reason="Damaged",
        created_by=manager.id,
    )
    db.add(adj_tx)
    db.flush()
    db.add(models.TransactionItem(
        transaction_id=adj_tx.id,
        product_id=prod.id,
        quantity=Decimal("47.000"),  # Physical count = 47 kg (50 - 3)
    ))
    db.commit()

    engine.validate_transaction(adj_tx.id, manager)

    db.refresh(stock_rack_a)
    db.refresh(stock_prod_floor)
    total_stock_after_adj = stock_rack_a.on_hand + stock_prod_floor.on_hand
    assert stock_rack_a.on_hand == Decimal("47.000")
    assert stock_prod_floor.on_hand == Decimal("30.000")
    assert total_stock_after_adj == Decimal("77.000")
    steps.append({
        "step": 7,
        "action": "Adjust -3 kg damaged",
        "result": {
            "Rack A": float(stock_rack_a.on_hand),
            "Production Floor": float(stock_prod_floor.on_hand),
            "Total": float(total_stock_after_adj),
        },
    })

    # 8. Open Move History
    recent_moves = (
        db.query(models.Transaction)
        .filter(models.Transaction.id.in_([rec_tx.id, trf_tx.id, del_tx.id, adj_tx.id]))
        .order_by(models.Transaction.id.asc())
        .all()
    )
    steps.append({
        "step": 8,
        "action": "Open Move History",
        "moves_count": len(recent_moves),
        "references": [m.reference for m in recent_moves],
    })

    # 9. Open Stock Ledger
    ledger_entries = (
        db.query(models.StockLedger)
        .filter(models.StockLedger.product_id == prod.id)
        .order_by(models.StockLedger.id.desc())
        .limit(5)
        .all()
    )
    steps.append({
        "step": 9,
        "action": "Open Stock Ledger",
        "ledger_entries_count": len(ledger_entries),
        "recent_movements": [
            f"{e.movement_type}: {e.quantity_change} kg (Before: {e.quantity_before}, After: {e.quantity_after})"
            for e in ledger_entries
        ],
    })

    # 10. Open Inventory Intelligence
    steps.append({
        "step": 10,
        "action": "Open Inventory Intelligence",
        "current_stock": float(total_stock_after_adj),
        "reorder_level": float(prod.reorder_point),
        "status": "NORMAL" if total_stock_after_adj > prod.reorder_point else "LOW STOCK",
    })

    return {
        "status": "success",
        "demo": "Section 50 Required Demo Flow",
        "final_stock": {
            "Main Warehouse (Rack A)": 70.0 - 20.0 - 3.0,
            "Production Floor": 30.0,
            "Total": 77.0,
        },
        "steps": steps,
    }


# ============================================================
# 51. ADVANCED DEMO EXECUTION
# ============================================================
@router.post("/demo/section-51")
def run_section_51_advanced_demo_flow(db: Session = Depends(get_db)):
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
    engine = InventoryTransactionEngine(db)
    seed = seed_demo_data(db)
    manager = seed["users"]["manager"]
    chair = seed["products"]["Chair"]
    rack_b = seed["locations"]["Rack B"]

    steps = []

    # 1. Available stock = 5
    stock = db.query(models.Stock).filter_by(product_id=chair.id, location_id=rack_b.id).first()
    if not stock:
        stock = models.Stock(product_id=chair.id, location_id=rack_b.id, on_hand=Decimal("5.000"), reserved=Decimal("0.000"))
        db.add(stock)
    else:
        stock.on_hand = Decimal("5.000")
        stock.reserved = Decimal("0.000")
    db.commit()
    db.refresh(stock)

    assert stock.free_to_use == Decimal("5.000")
    steps.append({"stage": 1, "state": "Initial Available Stock", "on_hand": 5.0, "reserved": 0.0, "free_to_use": 5.0})

    # 2. Create delivery: 20 -> Result: WAITING
    del_tx = models.Transaction(
        reference="DEL-DEMO-ADV-20",
        type=TransactionType.DELIVERY,
        status=TransactionStatus.DRAFT,
        source_location_id=rack_b.id,
        contact="Mega Office Ltd",
        created_by=manager.id,
    )
    db.add(del_tx)
    db.flush()
    db.add(models.TransactionItem(
        transaction_id=del_tx.id,
        product_id=chair.id,
        quantity=Decimal("20.000"),
    ))
    db.commit()

    # Attempt prepare delivery -> 5 < 20 -> Result: WAITING
    engine.prepare_delivery(del_tx.id, manager)
    db.refresh(del_tx)
    db.refresh(stock)

    assert del_tx.status == TransactionStatus.WAITING
    assert stock.reserved == Decimal("0.000")
    assert stock.free_to_use == Decimal("5.000")
    steps.append({"stage": 2, "state": "Delivery 20 Requested", "delivery_status": del_tx.status.value, "reason": "Insufficient stock (5 < 20)"})

    # 3. Then receive: 15
    rec_tx = models.Transaction(
        reference="REC-DEMO-ADV-15",
        type=TransactionType.RECEIPT,
        status=TransactionStatus.READY,
        destination_location_id=rack_b.id,
        contact="Chair Manufacturer Inc",
        created_by=manager.id,
    )
    db.add(rec_tx)
    db.flush()
    db.add(models.TransactionItem(
        transaction_id=rec_tx.id,
        product_id=chair.id,
        quantity=Decimal("15.000"),
    ))
    db.commit()

    # Validate receipt: triggers step 4 automatic check_waiting_deliveries
    engine.validate_transaction(rec_tx.id, manager)

    db.refresh(del_tx)
    db.refresh(stock)

    # 4. System checks waiting deliveries -> Delivery becomes: READY & System reserves stock
    # on_hand was 5 + 15 = 20
    # delivery requested 20 -> delivery status is now READY!
    # reserved = 20, free_to_use = 0
    assert del_tx.status == TransactionStatus.READY
    assert stock.on_hand == Decimal("20.000")
    assert stock.reserved == Decimal("20.000")
    assert stock.free_to_use == Decimal("0.000")
    steps.append({
        "stage": 3,
        "state": "Received 15 units & Checked Waiting Deliveries",
        "delivery_status": del_tx.status.value,
        "on_hand": float(stock.on_hand),
        "reserved": float(stock.reserved),
        "free_to_use": float(stock.free_to_use),
    })

    # 5. Validate. Delivery becomes: DONE. Stock is correctly reduced.
    engine.validate_transaction(del_tx.id, manager)
    db.refresh(del_tx)
    db.refresh(stock)

    assert del_tx.status == TransactionStatus.DONE
    assert stock.on_hand == Decimal("0.000")
    assert stock.reserved == Decimal("0.000")
    assert stock.free_to_use == Decimal("0.000")
    steps.append({
        "stage": 4,
        "state": "Delivery Validated to DONE",
        "delivery_status": del_tx.status.value,
        "final_on_hand": float(stock.on_hand),
        "final_reserved": float(stock.reserved),
        "final_free_to_use": float(stock.free_to_use),
        "reduced_correctly": True,
    })

    return {
        "status": "success",
        "demo": "Section 51 Advanced Demo Flow",
        "delivery_reference": del_tx.reference,
        "final_stock": 0.0,
        "steps": steps,
    }
