import datetime
from decimal import Decimal
from typing import List, Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, Header, status, Query
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..core.dependencies import get_current_user, require_manager, check_transaction_cancellation_permission
from ..services.inventory_engine import InventoryTransactionEngine
from ..services.reference_service import generate_transaction_reference
from ..models.transaction import TransactionType, TransactionStatus

router = APIRouter(prefix="/adjustments", tags=["Inventory Adjustments (Section 23)"])

VALID_REASONS = ["Damaged", "Lost", "Counting Error", "Found Stock", "Other"]


class AdjustmentCreatePayload(BaseModel):
    location_id: int
    product_id: int
    physical_count: Optional[float] = None
    counted_quantity: Optional[float] = None
    reason: str = "Counting Error"


def _serialize_adjustment(tx: models.Transaction, db: Session) -> dict:
    first_item = tx.items[0] if tx.items else None
    prod_name = first_item.product.name if first_item and first_item.product else "Unknown Product"
    prod_sku = first_item.product.sku if first_item and first_item.product else ""
    unit = first_item.product.unit_of_measure if first_item and first_item.product else "unit"

    loc = tx.source_location or tx.destination_location
    loc_id = loc.id if loc else 0
    loc_name = loc.name if loc else "Unknown Location"
    wh = loc.warehouse if loc else None
    wh_id = wh.id if wh else 0
    wh_name = wh.name if wh else "Unknown Warehouse"

    # Fetch live stock row
    stock_row = None
    if first_item and loc_id:
        stock_row = (
            db.query(models.Stock)
            .filter_by(product_id=first_item.product_id, location_id=loc_id)
            .first()
        )

    # If DONE, use recorded delta and current/recorded count
    if tx.status == TransactionStatus.DONE and first_item:
        physical_count = float(first_item.quantity)
        difference = float(first_item.adjustment_delta) if first_item.adjustment_delta is not None else 0.0
        system_quantity = physical_count - difference
    else:
        # If DRAFT, calculate live against current on_hand
        current_on_hand = float(stock_row.on_hand) if stock_row else 0.0
        physical_count = float(first_item.quantity) if first_item else current_on_hand
        system_quantity = current_on_hand
        difference = physical_count - system_quantity

    reserved_qty = float(stock_row.reserved) if stock_row else 0.0

    # Fetch ledger entry if DONE
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
        "move_type": "adjustment",
        "type": "ADJUSTMENT",
        "status": str(tx.status.value if hasattr(tx.status, "value") else tx.status).lower(),
        "status_raw": str(tx.status.value if hasattr(tx.status, "value") else tx.status),
        # Section 23 Mandatory Fields
        "product_id": first_item.product_id if first_item else 0,
        "product_name": prod_name,
        "sku": prod_sku,
        "unit": unit,
        "warehouse_id": wh_id,
        "warehouse_name": wh_name,
        "location_id": loc_id,
        "location_name": loc_name,
        "system_quantity": system_quantity,
        "physical_count": physical_count,
        "difference": difference,
        "reason": tx.reason or "Counting Error",
        "reserved": reserved_qty,
        "created_by": tx.created_by,
        "validated_by": tx.validated_by,
        "created_at": tx.created_at.isoformat() if tx.created_at else None,
        "done_at": tx.validated_at.isoformat() if tx.validated_at else None,
        "ledger_entry": ledger_entry,
    }


@router.get("")
def list_adjustments(
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status: draft, done, canceled"),
    search: Optional[str] = Query(None, description="Search by reference, product, reason"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    List physical inventory adjustments (Section 23).
    """
    query = db.query(models.Transaction).filter(models.Transaction.type == TransactionType.ADJUSTMENT)

    if status_filter:
        s = status_filter.strip().upper()
        if hasattr(TransactionStatus, s):
            query = query.filter(models.Transaction.status == TransactionStatus[s])

    if search:
        term = f"%{search.strip()}%"
        query = query.filter(
            (models.Transaction.reference.ilike(term))
            | (models.Transaction.reason.ilike(term))
        )

    txs = query.order_by(models.Transaction.id.desc()).all()
    return [_serialize_adjustment(tx, db) for tx in txs]


@router.get("/{adjustment_id}")
def get_adjustment_detail(
    adjustment_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Adjustment Detail (Section 23).
    """
    tx = (
        db.query(models.Transaction)
        .filter(models.Transaction.id == adjustment_id, models.Transaction.type == TransactionType.ADJUSTMENT)
        .first()
    )
    if not tx:
        raise HTTPException(status_code=404, detail="Adjustment not found")
    return _serialize_adjustment(tx, db)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_adjustment(
    payload: AdjustmentCreatePayload,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Section 23: Warehouse Staff can create.
    Reconciles System Quantity with Physical Quantity.
    Fields: Product, Warehouse, Location, System Quantity, Physical Count, Difference, Reason.
    Reasons: Damaged, Lost, Counting Error, Found Stock, Other.
    """
    loc = db.query(models.Location).filter(models.Location.id == payload.location_id).first()
    if not loc:
        raise HTTPException(status_code=400, detail="Invalid location")

    product = db.query(models.Product).filter(models.Product.id == payload.product_id).first()
    if not product:
        raise HTTPException(status_code=400, detail="Invalid product")

    # Determine physical count
    count = payload.physical_count if payload.physical_count is not None else payload.counted_quantity
    if count is None or count < 0:
        raise HTTPException(status_code=400, detail="Physical count must be a non-negative number")

    wh_code = loc.warehouse.short_code if loc.warehouse else "WH"
    reference = generate_transaction_reference(db, TransactionType.ADJUSTMENT, wh_code)

    # Initial status is DRAFT
    tx = models.Transaction(
        reference=reference,
        type=TransactionType.ADJUSTMENT,
        status=TransactionStatus.DRAFT,
        source_location_id=loc.id,
        destination_location_id=loc.id,
        party_name="Physical Inventory Count",
        reason=payload.reason or "Counting Error",
        schedule_date=datetime.datetime.utcnow(),
        created_by=user.id,
    )
    db.add(tx)
    db.flush()

    item = models.TransactionItem(
        transaction_id=tx.id,
        product_id=product.id,
        quantity=Decimal(str(count)),
    )
    db.add(item)
    db.commit()
    db.refresh(tx)

    return _serialize_adjustment(tx, db)


@router.post("/{adjustment_id}/validate")
def validate_adjustment(
    adjustment_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(require_manager),
    idempotency_key: Optional[str] = Header(None, alias="Idempotency-Key"),
    x_idempotency_key: Optional[str] = Header(None, alias="X-Idempotency-Key"),
):
    """
    Section 23 Rules:
    - Inventory Manager validates (enforced by require_manager).
    - Adjustment cannot result in: on_hand < reserved.
    - Adjustment must create a ledger entry.
    - No direct stock editing.
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == adjustment_id).first()
    if not tx or tx.type != TransactionType.ADJUSTMENT:
        raise HTTPException(status_code=404, detail="Adjustment not found")

    if tx.status == TransactionStatus.CANCELED:
        raise HTTPException(status_code=400, detail="Cannot validate a canceled adjustment")

    effective_key = idempotency_key or x_idempotency_key
    # Authoritative 13-step transaction engine validation
    engine = InventoryTransactionEngine(db)
    validated_tx = engine.validate_transaction(
        transaction_id=tx.id,
        user=user,
        idempotency_key=effective_key,
    )
    return _serialize_adjustment(validated_tx, db)


@router.post("/{adjustment_id}/cancel")
def cancel_adjustment(
    adjustment_id: int,
    db: Session = Depends(get_db),
    user: models.User = Depends(get_current_user),
):
    """
    Section 6 & 16: Cancel Adjustment.
    Staff can cancel own; Managers can cancel any.
    """
    tx = db.query(models.Transaction).filter(models.Transaction.id == adjustment_id).first()
    if not tx or tx.type != TransactionType.ADJUSTMENT:
        raise HTTPException(status_code=404, detail="Adjustment not found")

    if tx.status == TransactionStatus.DONE:
        raise HTTPException(status_code=400, detail="Cannot cancel a completed (DONE) adjustment")

    check_transaction_cancellation_permission(tx.created_by, user)

    engine = InventoryTransactionEngine(db)
    canceled_tx = engine.cancel_transaction(transaction_id=tx.id, user=user)
    return _serialize_adjustment(canceled_tx, db)
