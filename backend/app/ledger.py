from sqlalchemy.orm import Session
from sqlalchemy import func
from . import models


def get_on_hand(db: Session, product_id: int, location_id: int = None) -> float:
    """
    Computes on_hand from models.Stock.
    If location_id is None, computes total across all locations for that product.
    """
    q = db.query(func.coalesce(func.sum(models.Stock.on_hand), 0.0)).filter(
        models.Stock.product_id == product_id
    )
    if location_id is not None:
        q = q.filter(models.Stock.location_id == location_id)
    return float(q.scalar() or 0.0)


def get_reserved(db: Session, product_id: int, location_id: int = None) -> float:
    """
    Computes reserved from models.Stock.
    If location_id is None, computes total across all locations for that product.
    """
    q = db.query(func.coalesce(func.sum(models.Stock.reserved), 0.0)).filter(
        models.Stock.product_id == product_id
    )
    if location_id is not None:
        q = q.filter(models.Stock.location_id == location_id)
    return float(q.scalar() or 0.0)


def next_reference(db: Session, warehouse_code: str, operation_code: str) -> str:
    """
    Generates references like WH/IN/0001 following the pattern:
    <Warehouse>/<Operation>/<ID>
    """
    count = db.query(models.StockMove).filter(
        models.StockMove.reference.like(f"{warehouse_code}/{operation_code}/%")
    ).count()
    next_id = count + 1
    return f"{warehouse_code}/{operation_code}/{next_id:04d}"


def get_or_create_virtual_location(db: Session, name: str, short_code: str) -> models.Location:
    loc = db.query(models.Location).filter(models.Location.name == name, models.Location.is_virtual == True).first()  # noqa: E712
    if loc:
        return loc
    loc = models.Location(name=name, short_code=short_code, warehouse_id=None, is_virtual=True)
    db.add(loc)
    db.commit()
    db.refresh(loc)
    return loc


def serialize_move(move: models.StockMove) -> dict:
    return {
        "id": move.id,
        "reference": move.reference,
        "move_type": move.move_type,
        "product_id": move.product_id,
        "product_name": move.product.name if move.product else "",
        "from_location_id": move.from_location_id,
        "from_location_name": move.from_location.name if move.from_location else None,
        "to_location_id": move.to_location_id,
        "to_location_name": move.to_location.name if move.to_location else None,
        "quantity": move.quantity,
        "status": move.status,
        "contact": move.contact,
        "scheduled_date": move.scheduled_date,
        "created_at": move.created_at,
        "done_at": move.done_at,
    }
