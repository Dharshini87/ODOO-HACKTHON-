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

router = APIRouter(prefix="/transfers", tags=["Internal Transfers (Section 22)"])


def _serialize_transfer(tx: models.Transaction, db: Session) -> dict:
    first_item = tx.items[0] if tx.items else None
    prod_name = first_item.product.name if first_item and first_item.product else "Unknown Product"
    prod_sku = first_item.product.sku if first_item and first_item.product else ""
    qty = float(first_item.quantity) if first_item else 0.0

    src_name = tx.source_location.name if tx.source_location else "Source Location"
    dest_name = tx.destination_location.name if tx.destination_location else "Destination Location"

    # Fetch source stock for free_to_use validation preview
    src_stock = None
    if first_item and tx.source_location_id:
        src_stock = (
            db.query(models.Stock)
            .filter_by(product_id=first_item.product_id, location_id=tx.source_location_id)
            .first()
        )
    src_on_hand = float(src_stock.on_hand) if src_stock else 0.0
    src_reserved = float(src_stock.reserved) if src_stock else 0.0
    src_free = float(src_stock.free_to_use) if src_stock else 0.0

    # Fetch destination stock
    dst_stock = None
    if first_item and tx.destination_location_id:
        dst_stock = (
            db.query(models.Stock)
            .filter_by(product_id=first_item.product_id, location_id=tx.destination_location_id)
            .first()
        )
    dst_on_hand = float(dst_stock.on_hand) if dst_stock else 0.0

    # Fetch ledger entries if DONE (TRANSFER_OUT and TRANSFER_IN)
    transfer_out_ledger = None
    transfer_in_ledger = None
    if tx.status == TransactionStatus.DONE and first_item:
        ledgers = (
            db.query(models.StockLedger)
            .filter_by(transaction_id=tx.id, product_id=first_item.product_id)
            .all()
        )
        for led in ledgers:
            if led.movement_type == "TRANSFER_OUT":
                transfer_out_ledger = {
                    "location_id": led.location_id,
                    "quantity_before": float(led.quantity_before),
                    "quantity_change": float(led.quantity_change),
                    "quantity_after": float(led.quantity_after),
                    "movement_type": led.movement_type,
                }
            elif led.movement_type == "TRANSFER_IN":
                transfer_in_ledger = {
                    "location_id": led.location_id,
                    "quantity_before": float(led.quantity_before),
                    "quantity_change": float(led.quantity_change),
                    "quantity_after": float(led.quantity_after),
                    "movement_type": led.movement_type,
                }

    items_list = []
    for it in tx.items:
        items_list.append({
            "id": it.id,
            "product_id": it.product_id,
            "product_name": it.product.name if it.product else "",
            "sku": it.product.sku if it.product else "",
            "quantity": float(it.quantity),
            "unit": it.product.unit_of_measure if it.product else "unit",
        })

    return {
        "id": tx.id,
        "reference": tx.reference,
        "move_type": "transfer",
        "type": "TRANSFER",
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
        "contact": tx.contact or "Internal Transfer",
        "created_at": tx.created_at.isoformat() if tx.created_at else None,
        "done_at": tx.validated_at.isoformat() if tx.validated_at else None,
        "schedule_date": tx.schedule_date.isoformat() if tx.schedule_date else None,
        "validated_by": tx.validated_by,
        # Section 22 Free-to-use Source & Destination Metrics
        "source_on_hand": src_on_hand,
        "source_reserved": src_reserved,
        "source_free_to_use": src_free,
        "destination_on_hand": dst_on_hand,
        "items": items_list,
        "transfer_out_ledger": transfer_out_ledger,
        "transfer_in_ledger": transfer_in_ledger,
    }


@router.get("")
def list_transfers(
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status: draft, ready, done, canceled"),
    search: Optional[str] = Query(None, description="Search reference, product, source or dest location"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    List Internal Transfers (Section 22).
    """
    query = db.query(models.Transaction).filter(models.Transaction.type == TransactionType.TRANSFER)

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
    return [_serialize_transfer(tx, db) for tx in txs]


@router.get("/{transfer_id}")
def get_transfer_detail(
    transfer_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Get Transfer Detail (Section 22).
    """
    tx = (
        db.query(models.Transaction)
        .filter(models.Transaction.id == transfer_id, models.Transaction.type == TransactionType.TRANSFER)
        .first()
    )
    if not tx:
        raise HTTPException(status_code=404, detail="Transfer not found")
    return _serialize_transfer(tx, db)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_transfer(
    payload: schemas.StockMoveIn,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Create Internal Transfer (Section 22).
    Validates:
      - Source and destination must be valid and differ.
      - Product exists.
      - Reference generated: WH/TR/xxxx (Section 41).
    """
    if not payload.from_location_id or not payload.to_location_id:
        raise HTTPException(status_code=400, detail="Both source and destination locations are required")

    if payload.from_location_id == payload.to_location_id:
        raise HTTPException(status_code=400, detail="Source and destination locations must differ")

    from_loc = db.query(models.Location).filter(models.Location.id == payload.from_location_id).first()
    if not from_loc:
        raise HTTPException(status_code=400, detail="Invalid source location")

    to_loc = db.query(models.Location).filter(models.Location.id == payload.to_location_id).first()
    if not to_loc:
        raise HTTPException(status_code=400, detail="Invalid destination location")

    product = db.query(models.Product).filter(models.Product.id == payload.product_id).first()
    if not product:
        raise HTTPException(status_code=400, detail="Invalid product")

    qty = Decimal(str(payload.quantity))
    if qty <= Decimal("0"):
        raise HTTPException(status_code=400, detail="Quantity must be greater than zero")

    wh_code = from_loc.warehouse.short_code if from_loc.warehouse else "WH"
    reference = generate_transaction_reference(db, TransactionType.TRANSFER, wh_code)

    # Initial status is DRAFT
    tx = models.Transaction(
        reference=reference,
        type=TransactionType.TRANSFER,
        status=TransactionStatus.DRAFT,
        source_location_id=from_loc.id,
        destination_location_id=to_loc.id,
        party_name="Internal Move",
        contact=payload.contact or f"{from_loc.name} -> {to_loc.name}",
        schedule_date=payload.scheduled_date or datetime.datetime.utcnow(),
        created_by=user.id,
    )
    db.add(tx)
    db.flush()

    item = models.TransactionItem(
        transaction_id=tx.id,
        product_id=product.id,
        quantity=qty,
    )
    db.add(item)
    db.commit()
    db.refresh(tx)

    return _serialize_transfer(tx, db)


@router.post("/{transfer_id}/ready")
def mark_transfer_ready(
    transfer_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Section 22: Check Free-to-use stock and mark READY.
    Transfer must use FREE TO USE stock only.
    Reserved inventory cannot be transferred.
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == transfer_id).first()
    if not tx or tx.type != TransactionType.TRANSFER:
        raise HTTPException(status_code=404, detail="Transfer not found")

    if tx.status == TransactionStatus.DONE:
        raise HTTPException(status_code=400, detail="Transfer is already validated (DONE)")
    if tx.status == TransactionStatus.CANCELED:
        raise HTTPException(status_code=400, detail="Cannot mark a canceled transfer as READY")

    first_item = tx.items[0] if tx.items else None
    if not first_item:
        raise HTTPException(status_code=400, detail="Transfer has no items")

    stock = (
        db.query(models.Stock)
        .filter_by(product_id=first_item.product_id, location_id=tx.source_location_id)
        .first()
    )
    free = stock.free_to_use if stock else Decimal("0.000")
    needed = Decimal(str(first_item.quantity))

    if free < needed:
        tx.status = TransactionStatus.WAITING
        db.commit()
        raise HTTPException(
            status_code=400,
            detail=f"Transfer requires FREE TO USE stock only. Free to use: {free}, requested: {needed}. Reserved stock cannot be transferred.",
        )

    tx.status = TransactionStatus.READY
    db.commit()
    db.refresh(tx)
    return _serialize_transfer(tx, db)


@router.post("/{transfer_id}/validate")
def validate_transfer(
    transfer_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key"),
    x_idempotency_key: Optional[str] = Header(None, alias="X-Idempotency-Key"),
):
    """
    Section 22: Validate Transfer.
    Must use FREE TO USE stock only.
    Reserved inventory cannot be transferred.

    Atomically:
      Source: on_hand -= qty
      Destination: on_hand += qty
      Creates TRANSFER_OUT ledger entry
      Creates TRANSFER_IN ledger entry
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == transfer_id).first()
    if not tx or tx.type != TransactionType.TRANSFER:
        raise HTTPException(status_code=404, detail="Transfer not found")

    if tx.status == TransactionStatus.CANCELED:
        raise HTTPException(status_code=400, detail="Cannot validate a canceled transfer")

    effective_key = idempotency_key or x_idempotency_key
    engine = InventoryTransactionEngine(db)
    validated_tx = engine.validate_transaction(
        transaction_id=tx.id,
        user=user,
        idempotency_key=effective_key,
    )
    return _serialize_transfer(validated_tx, db)


@router.post("/{transfer_id}/cancel")
def cancel_transfer(
    transfer_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Section 6 & 16: Cancel Transfer.
    Staff can cancel own; Managers can cancel any.
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == transfer_id).first()
    if not tx or tx.type != TransactionType.TRANSFER:
        raise HTTPException(status_code=404, detail="Transfer not found")

    if tx.status == TransactionStatus.DONE:
        raise HTTPException(status_code=400, detail="Cannot cancel a completed (DONE) transfer")

    check_transaction_cancellation_permission(tx.created_by, user)

    engine = InventoryTransactionEngine(db)
    canceled_tx = engine.cancel_transaction(transaction_id=tx.id, user=user)
    return _serialize_transfer(canceled_tx, db)
