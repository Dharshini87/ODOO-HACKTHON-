from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from .. import models, schemas, auth, ledger
from ..database import get_db

router = APIRouter(prefix="/stock", tags=["Stock"])


@router.get("", response_model=List[schemas.ProductStockOut])
def get_stock_overview(
    location_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    products = db.query(models.Product).all()
    result = []
    for p in products:
        on_hand = ledger.get_on_hand(db, p.id, location_id)
        reserved = ledger.get_reserved(db, p.id, location_id)
        stat = "OUT OF STOCK" if on_hand == 0 else ("LOW STOCK" if on_hand <= p.reorder_point else "NORMAL")
        wh_name = "Main Warehouse"
        loc_name = "Rack A"
        if location_id:
            loc = db.query(models.Location).filter(models.Location.id == location_id).first()
            if loc:
                loc_name = loc.name
                if loc.warehouse:
                    wh_name = loc.warehouse.name
        result.append(schemas.ProductStockOut(
            product_id=p.id,
            product_name=p.name,
            sku=p.sku,
            cost_per_unit=p.cost_per_unit,
            on_hand=on_hand,
            reserved=reserved,
            free_to_use=on_hand - reserved,
            reorder_point=p.reorder_point,
            low_stock=on_hand <= p.reorder_point,
            warehouse_name=wh_name,
            location_name=loc_name,
            unit_of_measure=p.unit_of_measure or "kg",
            status=stat,
        ))
    return result
