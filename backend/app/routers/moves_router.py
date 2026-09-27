from typing import List, Optional
import datetime
from decimal import Decimal
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_

from .. import models, schemas, auth
from ..database import get_db

router = APIRouter(tags=["Moves and Ledger"])


# ============================================================
# 24. STOCK LEDGER
# ============================================================
@router.get("/ledger", response_model=List[schemas.StockLedgerOut])
@router.get("/stock-ledger", response_model=List[schemas.StockLedgerOut])
@router.get("/stock/ledger", response_model=List[schemas.StockLedgerOut])
def list_stock_ledger(
    product_id: Optional[int] = Query(None, description="Filter by Product ID"),
    location_id: Optional[int] = Query(None, description="Filter by Location ID"),
    movement_type: Optional[str] = Query(None, description="RECEIPT, DELIVERY, TRANSFER_IN, TRANSFER_OUT, ADJUSTMENT"),
    transaction_id: Optional[int] = Query(None, description="Filter by Transaction ID"),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """
    Section 24: STOCK LEDGER
    Fields:
      - id
      - transaction_id
      - product_id
      - location_id
      - quantity_before
      - quantity_change
      - quantity_after
      - movement_type (RECEIPT, DELIVERY, TRANSFER_IN, TRANSFER_OUT, ADJUSTMENT)
      - created_at
    Ledger is: READ ONLY, APPEND ONLY, IMMUTABLE.
    """
    q = db.query(models.StockLedger)

    if product_id is not None:
        q = q.filter(models.StockLedger.product_id == product_id)
    if location_id is not None:
        q = q.filter(models.StockLedger.location_id == location_id)
    if movement_type:
        clean_type = movement_type.strip().upper()
        q = q.filter(models.StockLedger.movement_type == clean_type)
    if transaction_id is not None:
        q = q.filter(models.StockLedger.transaction_id == transaction_id)

    entries = q.order_by(models.StockLedger.id.desc()).offset(skip).limit(limit).all()

    result = []
    for e in entries:
        prod_name = e.product.name if e.product else ""
        sku = e.product.sku if e.product else ""
        loc_name = e.location.name if e.location else ""
        wh_name = e.location.warehouse.name if (e.location and e.location.warehouse) else None

        qty_before = float(e.get_quantity_before())
        qty_change = float(e.quantity_change or 0.0)
        qty_after = float(e.get_quantity_after())

        result.append(schemas.StockLedgerOut(
            id=e.id,
            transaction_id=e.transaction_id,
            product_id=e.product_id,
            product_name=prod_name,
            sku=sku,
            location_id=e.location_id,
            location_name=loc_name,
            warehouse_name=wh_name,
            quantity_before=qty_before,
            quantity_change=qty_change,
            quantity_after=qty_after,
            movement_type=e.movement_type,
            reference=e.reference,
            created_at=e.created_at,
        ))
    return result


# ============================================================
# 25. MOVE HISTORY (DERIVED)
# ============================================================
@router.get("/moves", response_model=List[schemas.DerivedMoveOut])
def get_moves(
    search: Optional[str] = Query(None, description="Search Reference, Contact, SKU"),
    type: Optional[str] = Query(None, description="RECEIPT, DELIVERY, TRANSFER, ADJUSTMENT"),
    status: Optional[str] = Query(None, description="DRAFT, WAITING, READY, DONE, CANCELED"),
    product_id: Optional[int] = Query(None, description="Filter by Product ID"),
    warehouse_id: Optional[int] = Query(None, description="Filter by Warehouse ID"),
    location_id: Optional[int] = Query(None, description="Filter by Location ID"),
    date_from: Optional[datetime.date] = Query(None, description="Filter from Date (YYYY-MM-DD)"),
    date_to: Optional[datetime.date] = Query(None, description="Filter to Date (YYYY-MM-DD)"),
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """
    Section 25: MOVE HISTORY
    Rule: Do NOT create a separate move history table.
    Derive data from:
      - transactions
      - transaction_items
      - stock_ledger
    Mobile display: Reference, Date, Contact, From, To, Quantity, Status
    Search: Reference, Contact, SKU
    Filters: Type, Status, Product, Warehouse, Location, Date
    Support: List view, Kanban view.
    """
    # Query transactions joined with items
    q = (
        db.query(models.Transaction)
        .join(models.TransactionItem, models.Transaction.id == models.TransactionItem.transaction_id)
        .join(models.Product, models.TransactionItem.product_id == models.Product.id)
    )

    if type:
        clean_type = type.strip().upper()
        q = q.filter(models.Transaction.type == clean_type)

    if status:
        clean_stat = status.strip().upper()
        q = q.filter(models.Transaction.status == clean_stat)

    if product_id is not None:
        q = q.filter(models.TransactionItem.product_id == product_id)

    if location_id is not None:
        q = q.filter(
            or_(
                models.Transaction.source_location_id == location_id,
                models.Transaction.destination_location_id == location_id,
            )
        )

    if warehouse_id is not None:
        from_loc_sub = db.query(models.Location.id).filter(models.Location.warehouse_id == warehouse_id).subquery()
        to_loc_sub = db.query(models.Location.id).filter(models.Location.warehouse_id == warehouse_id).subquery()
        q = q.filter(
            or_(
                models.Transaction.source_location_id.in_(from_loc_sub),
                models.Transaction.destination_location_id.in_(to_loc_sub),
            )
        )

    if date_from:
        start_dt = datetime.datetime.combine(date_from, datetime.time.min)
        q = q.filter(models.Transaction.created_at >= start_dt)

    if date_to:
        end_dt = datetime.datetime.combine(date_to, datetime.time.max)
        q = q.filter(models.Transaction.created_at <= end_dt)

    if search:
        s = f"%{search.strip()}%"
        q = q.filter(
            or_(
                models.Transaction.reference.ilike(s),
                models.Transaction.contact.ilike(s),
                models.Transaction.party_name.ilike(s),
                models.Product.sku.ilike(s),
                models.Product.name.ilike(s),
            )
        )

    # Distinct transactions ordered newest first
    tx_list = q.order_by(models.Transaction.id.desc()).offset(skip).limit(limit).all()

    results: List[schemas.DerivedMoveOut] = []

    for tx in tx_list:
        tx_type_str = tx.type.value if hasattr(tx.type, "value") else str(tx.type)
        tx_stat_str = tx.status.value if hasattr(tx.status, "value") else str(tx.status)
        contact_str = tx.contact or tx.party_name
        src_loc_name = tx.source_location.name if tx.source_location else None
        dst_loc_name = tx.destination_location.name if tx.destination_location else None
        tx_date = tx.schedule_date or tx.created_at

        # Fetch any ledger entries recorded for this transaction
        ledger_rows = (
            db.query(models.StockLedger)
            .filter(models.StockLedger.transaction_id == tx.id)
            .order_by(models.StockLedger.id.asc())
            .all()
        )
        ledger_outs = [
            schemas.StockLedgerOut(
                id=lr.id,
                transaction_id=lr.transaction_id,
                product_id=lr.product_id,
                product_name=lr.product.name if lr.product else "",
                sku=lr.product.sku if lr.product else "",
                location_id=lr.location_id,
                location_name=lr.location.name if lr.location else "",
                warehouse_name=lr.location.warehouse.name if (lr.location and lr.location.warehouse) else None,
                quantity_before=float(lr.get_quantity_before()),
                quantity_change=float(lr.quantity_change or 0.0),
                quantity_after=float(lr.get_quantity_after()),
                movement_type=lr.movement_type,
                reference=lr.reference,
                created_at=lr.created_at,
            )
            for lr in ledger_rows
        ]

        for item in tx.items:
            # If product filter applied, only include matching items
            if product_id is not None and item.product_id != product_id:
                continue

            results.append(schemas.DerivedMoveOut(
                id=tx.id,
                reference=tx.reference,
                date=tx_date,
                contact=contact_str,
                from_location=src_loc_name,
                from_location_id=tx.source_location_id,
                to_location=dst_loc_name,
                to_location_id=tx.destination_location_id,
                product_id=item.product_id,
                product_name=item.product.name if item.product else "",
                sku=item.product.sku if item.product else "",
                quantity=float(item.quantity or 0.0),
                status=tx_stat_str,
                type=tx_type_str,
                created_at=tx.created_at,
                ledger_entries=[e for e in ledger_outs if e.product_id == item.product_id],
            ))

    return results
