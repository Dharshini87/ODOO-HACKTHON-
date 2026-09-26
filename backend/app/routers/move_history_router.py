from typing import List, Optional
import datetime
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from .. import models, schemas, auth, ledger
from ..database import get_db

router = APIRouter(prefix="/move-history", tags=["Move History"])


@router.get("", response_model=List[schemas.StockMoveOut])
def move_history(
    move_type: Optional[models.MoveType] = Query(None, description="Filter by Type (receipt, delivery, transfer, adjustment)"),
    status: Optional[models.MoveStatus] = Query(None, description="Filter by Status (draft, waiting, ready, done, cancelled)"),
    search: Optional[str] = Query(None, description="Search by Reference or Contact"),
    warehouse_id: Optional[int] = Query(None, description="Filter by Warehouse ID"),
    location_id: Optional[int] = Query(None, description="Filter by Location ID"),
    category_id: Optional[int] = Query(None, description="Filter by Product Category ID"),
    product_id: Optional[int] = Query(None, description="Filter by Product ID"),
    date_from: Optional[datetime.date] = Query(None, description="Filter from Date (YYYY-MM-DD)"),
    date_to: Optional[datetime.date] = Query(None, description="Filter to Date (YYYY-MM-DD)"),
    skip: int = Query(0, ge=0, description="Pagination offset"),
    limit: int = Query(100, ge=1, le=500, description="Pagination limit"),
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """
    Section 34: SEARCH AND FILTERING
    - Search by Reference, Contact
    - Filters: Type, Status, Warehouse, Location, Category, Product, Date
    - Backend filtering and pagination
    """
    q = db.query(models.StockMove)

    if move_type:
        q = q.filter(models.StockMove.move_type == move_type)
    if status:
        q = q.filter(models.StockMove.status == status)
    if search:
        like = f"%{search.strip()}%"
        q = q.filter((models.StockMove.reference.ilike(like)) | (models.StockMove.contact.ilike(like)))
    if product_id:
        q = q.filter(models.StockMove.product_id == product_id)
    if category_id:
        q = q.join(models.Product, models.StockMove.product_id == models.Product.id).filter(
            models.Product.category_id == category_id
        )
    if location_id:
        q = q.filter(
            (models.StockMove.from_location_id == location_id) | (models.StockMove.to_location_id == location_id)
        )
    if warehouse_id:
        # Join Location to check warehouse
        from_loc = db.query(models.Location.id).filter(models.Location.warehouse_id == warehouse_id).subquery()
        to_loc = db.query(models.Location.id).filter(models.Location.warehouse_id == warehouse_id).subquery()
        q = q.filter(
            (models.StockMove.from_location_id.in_(from_loc)) | (models.StockMove.to_location_id.in_(to_loc))
        )
    if date_from:
        start_dt = datetime.datetime.combine(date_from, datetime.time.min)
        q = q.filter(models.StockMove.created_at >= start_dt)
    if date_to:
        end_dt = datetime.datetime.combine(date_to, datetime.time.max)
        q = q.filter(models.StockMove.created_at <= end_dt)

    moves = q.order_by(models.StockMove.id.desc()).offset(skip).limit(limit).all()
    return [ledger.serialize_move(m) for m in moves]


@router.get("/last-incoming/{product_id}")
def last_incoming_for_product(
    product_id: int,
    location_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """Returns the timestamp & quantity of the most recent completed receipt for a product,
    optionally scoped to a specific warehouse location (used to monitor product freshness)."""
    q = db.query(models.StockMove).filter(
        models.StockMove.product_id == product_id,
        models.StockMove.move_type == models.MoveType.receipt,
        models.StockMove.status == models.MoveStatus.done,
    )
    if location_id:
        q = q.filter(models.StockMove.to_location_id == location_id)

    last = q.order_by(models.StockMove.done_at.desc()).first()
    if not last:
        return {"message": "No incoming stock recorded yet"}
    return ledger.serialize_move(last)
