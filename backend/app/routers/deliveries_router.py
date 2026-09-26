import datetime
from decimal import Decimal
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Header, status, Query
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..core.dependencies import get_current_user, check_transaction_cancellation_permission
from ..services.inventory_engine import InventoryTransactionEngine
from ..services.reference_service import generate_transaction_reference
from ..models.transaction import TransactionType, TransactionStatus

router = APIRouter(prefix="/deliveries", tags=["Deliveries (Sections 20, 21)"])


def _serialize_delivery(tx: models.Transaction, db: Session) -> dict:
    first_item = tx.items[0] if tx.items else None
    prod_name = first_item.product.name if first_item and first_item.product else "Unknown Product"
    prod_sku = first_item.product.sku if first_item and first_item.product else ""
    qty = float(first_item.quantity) if first_item else 0.0

    src_name = tx.source_location.name if tx.source_location else "Warehouse"
    dest_name = tx.party_name or (tx.destination_location.name if tx.destination_location else "Customer")

    # Fetch stock row for source location and product to compute Section 20 metrics
    stock_row = None
    if first_item and tx.source_location_id:
        stock_row = (
            db.query(models.Stock)
            .filter_by(product_id=first_item.product_id, location_id=tx.source_location_id)
            .first()
        )

    on_hand = float(stock_row.on_hand) if stock_row else 0.0
    reserved = float(stock_row.reserved) if stock_row else 0.0
    free_to_use = float(stock_row.free_to_use) if stock_row else 0.0
    requested = qty

    # Section 20 Shortage calculation:
    # If in DRAFT or WAITING, shortage = max(0, requested - free_to_use)
    # If in READY or DONE, stock is already reserved or deducted, so shortage = 0
    if tx.status in (TransactionStatus.DRAFT, TransactionStatus.WAITING):
        shortage = max(0.0, requested - free_to_use)
    else:
        shortage = 0.0

    items_list = []
    for it in tx.items:
        it_stock = None
        if tx.source_location_id:
            it_stock = (
                db.query(models.Stock)
                .filter_by(product_id=it.product_id, location_id=tx.source_location_id)
                .first()
            )
        it_on_hand = float(it_stock.on_hand) if it_stock else 0.0
        it_reserved = float(it_stock.reserved) if it_stock else 0.0
        it_free = float(it_stock.free_to_use) if it_stock else 0.0
        it_req = float(it.quantity)
        it_shortage = max(0.0, it_req - it_free) if tx.status in (TransactionStatus.DRAFT, TransactionStatus.WAITING) else 0.0

        items_list.append({
            "id": it.id,
            "product_id": it.product_id,
            "product_name": it.product.name if it.product else "",
            "sku": it.product.sku if it.product else "",
            "quantity": it_req,
            "unit": it.product.unit_of_measure if it.product else "unit",
            "on_hand": it_on_hand,
            "reserved": it_reserved,
            "free_to_use": it_free,
            "shortage": it_shortage,
        })

    # Ledger entry if DONE
    ledger_entry = None
    if tx.status == TransactionStatus.DONE and first_item:
        led = (
            db.query(models.StockLedger)
            .filter_by(transaction_id=tx.id, product_id=first_item.product_id)
            .first()
        )
        if led:
            ledger_entry = {
                "quantity_before": float(led.quantity_before),
                "quantity_change": float(led.quantity_change),
                "quantity_after": float(led.quantity_after),
                "movement_type": led.movement_type,
            }

    return {
        "id": tx.id,
        "reference": tx.reference,
        "move_type": "delivery",
        "type": "DELIVERY",
        "status": str(tx.status.value if hasattr(tx.status, "value") else tx.status).lower(),
        "status_raw": str(tx.status.value if hasattr(tx.status, "value") else tx.status),
        "product_id": first_item.product_id if first_item else 0,
        "product_name": prod_name,
        "sku": prod_sku,
        "from_location_id": tx.source_location_id or 0,
        "from_location_name": src_name,
        "to_location_id": tx.destination_location_id or 0,
        "to_location_name": dest_name,
        "quantity": qty,
        "contact": tx.contact or tx.party_name or "Customer",
        "created_at": tx.created_at.isoformat() if tx.created_at else None,
        "done_at": tx.validated_at.isoformat() if tx.validated_at else None,
        "schedule_date": tx.schedule_date.isoformat() if tx.schedule_date else None,
        "validated_by": tx.validated_by,
        # Section 20 Critical Stock Metrics
        "on_hand": on_hand,
        "reserved": reserved,
        "free_to_use": free_to_use,
        "requested": requested,
        "shortage": shortage,
        "is_waiting_for_stock": (tx.status == TransactionStatus.WAITING),
        "items": items_list,
        "ledger_entry": ledger_entry,
    }


@router.get("")
def list_deliveries(
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status: draft, waiting, ready, done, canceled"),
    search: Optional[str] = Query(None, description="Search by reference, product name, sku, contact"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    List deliveries (Section 20).
    Ordered newest-first.
    """
    query = db.query(models.Transaction).filter(models.Transaction.type == TransactionType.DELIVERY)

    if status_filter:
        s = status_filter.strip().upper()
        if hasattr(TransactionStatus, s):
            query = query.filter(models.Transaction.status == TransactionStatus[s])

    if search:
        term = f"%{search.strip()}%"
        query = query.filter(
            (models.Transaction.reference.ilike(term))
            | (models.Transaction.party_name.ilike(term))
            | (models.Transaction.contact.ilike(term))
        )

    txs = query.order_by(models.Transaction.id.desc()).all()
    return [_serialize_delivery(tx, db) for tx in txs]


@router.post("/process-waiting")
def process_waiting_deliveries(
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Section 21: WAITING -> READY automated check.
    Processes oldest-created-first.
    If ALL products available: reserve stock and transition WAITING -> READY.
    """
    engine = InventoryTransactionEngine(db)
    transitioned = engine.check_waiting_deliveries()
    return {
        "transitioned_count": len(transitioned),
        "transitioned_deliveries": [_serialize_delivery(tx, db) for tx in transitioned],
    }


@router.get("/{delivery_id}")
def get_delivery_detail(
    delivery_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Delivery Detail (Section 20: Draft, Waiting, Ready, Done).
    Returns Section 20 metrics: On Hand, Reserved, Free to Use, Requested, Shortage.
    """
    tx = (
        db.query(models.Transaction)
        .filter(models.Transaction.id == delivery_id, models.Transaction.type == TransactionType.DELIVERY)
        .first()
    )
    if not tx:
        raise HTTPException(status_code=404, detail="Delivery not found")
    return _serialize_delivery(tx, db)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_delivery(
    payload: schemas.StockMoveIn,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Create Outbound Delivery (Section 20).
    Initial status: DRAFT.
    Reference generated by backend: WH/OUT/xxxx (Section 41).
    """
    if not payload.from_location_id:
        raise HTTPException(status_code=400, detail="Source location is required for outbound deliveries")

    from_loc = db.query(models.Location).filter(models.Location.id == payload.from_location_id).first()
    if not from_loc:
        raise HTTPException(status_code=400, detail="Invalid source location")

    product = db.query(models.Product).filter(models.Product.id == payload.product_id).first()
    if not product:
        raise HTTPException(status_code=400, detail="Invalid product")

    wh_code = from_loc.warehouse.short_code if from_loc.warehouse else "WH"
    reference = generate_transaction_reference(db, TransactionType.DELIVERY, wh_code)

    tx = models.Transaction(
        reference=reference,
        type=TransactionType.DELIVERY,
        status=TransactionStatus.DRAFT,
        source_location_id=from_loc.id,
        destination_location_id=payload.to_location_id,
        party_name=payload.contact or "Customer",
        contact=payload.contact or "Customer",
        schedule_date=payload.scheduled_date or datetime.datetime.utcnow(),
        created_by=user.id,
    )
    db.add(tx)
    db.flush()

    item = models.TransactionItem(
        transaction_id=tx.id,
        product_id=product.id,
        quantity=Decimal(str(payload.quantity)),
    )
    db.add(item)
    db.commit()
    db.refresh(tx)

    return _serialize_delivery(tx, db)


@router.post("/{delivery_id}/ready")
def mark_delivery_ready(
    delivery_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Section 20: DRAFT / WAITING -> READY or WAITING
    Before allowing READY:
      free_to_use >= requested quantity
    If sufficient:
      DRAFT -> READY (reserves stock: reserved += requested)
    If insufficient:
      DRAFT -> WAITING (no reservation)
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == delivery_id).first()
    if not tx or tx.type != TransactionType.DELIVERY:
        raise HTTPException(status_code=404, detail="Delivery not found")

    engine = InventoryTransactionEngine(db)
    updated_tx = engine.prepare_delivery(tx.id, user)
    return _serialize_delivery(updated_tx, db)


@router.post("/{delivery_id}/validate")
def validate_delivery(
    delivery_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key"),
    x_idempotency_key: Optional[str] = Header(None, alias="X-Idempotency-Key"),
):
    """
    Section 20: Validate Delivery (READY -> DONE).
    Executes authoritative 13-step transaction engine:
      on_hand -= quantity
      reserved -= quantity
      Ledger: movement_type = DELIVERY, quantity_change = -quantity
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == delivery_id).first()
    if not tx or tx.type != TransactionType.DELIVERY:
        raise HTTPException(status_code=404, detail="Delivery not found")

    effective_key = idempotency_key or x_idempotency_key
    engine = InventoryTransactionEngine(db)

    # Check if duplicate request is already idempotent before status check
    idemp = engine.check_or_store_idempotency(effective_key, f"/api/transactions/{tx.id}/validate", user.id)
    if not (idemp and idemp.response_code == 200):
        if tx.status == TransactionStatus.WAITING:
            raise HTTPException(status_code=400, detail="Cannot validate a delivery waiting for stock")
        if tx.status == TransactionStatus.CANCELED:
            raise HTTPException(status_code=400, detail="Cannot validate a canceled delivery")

    validated_tx = engine.validate_transaction(
        transaction_id=tx.id,
        user=user,
        idempotency_key=effective_key,
    )
    return _serialize_delivery(validated_tx, db)


@router.post("/{delivery_id}/cancel")
def cancel_delivery(
    delivery_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Section 6 & 16: Cancel Delivery.
    Staff can cancel own; Managers can cancel any.
    If delivery was in READY status, releases reserved quantities.
    Triggers automated Section 21 check for any waiting deliveries.
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == delivery_id).first()
    if not tx or tx.type != TransactionType.DELIVERY:
        raise HTTPException(status_code=404, detail="Delivery not found")

    if tx.status == TransactionStatus.DONE:
        raise HTTPException(status_code=400, detail="Cannot cancel a completed (DONE) delivery")

    check_transaction_cancellation_permission(tx.created_by, user)

    engine = InventoryTransactionEngine(db)
    canceled_tx = engine.cancel_transaction(transaction_id=tx.id, user=user)
    return _serialize_delivery(canceled_tx, db)
