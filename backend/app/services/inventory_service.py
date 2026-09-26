from typing import List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import func
from .. import models, schemas

class InventoryService:
    def __init__(self, db: Session):
        self.db = db

    def get_on_hand(self, product_id: int, location_id: Optional[int] = None) -> float:
        """
        Stock on hand = total completed IN to location - total completed OUT from location.
        """
        in_query = self.db.query(func.coalesce(func.sum(models.StockMove.quantity), 0.0)).filter(
            models.StockMove.product_id == product_id,
            models.StockMove.status == models.MoveStatus.done,
        )
        out_query = self.db.query(func.coalesce(func.sum(models.StockMove.quantity), 0.0)).filter(
            models.StockMove.product_id == product_id,
            models.StockMove.status == models.MoveStatus.done,
        )

        if location_id is not None:
            in_query = in_query.filter(models.StockMove.to_location_id == location_id)
            out_query = out_query.filter(models.StockMove.from_location_id == location_id)
        else:
            in_query = in_query.join(models.Location, models.StockMove.to_location_id == models.Location.id).filter(
                models.Location.is_virtual == False
            )
            out_query = out_query.join(models.Location, models.StockMove.from_location_id == models.Location.id).filter(
                models.Location.is_virtual == False
            )

        total_in = in_query.scalar() or 0.0
        total_out = out_query.scalar() or 0.0
        return float(total_in - total_out)

    def get_reserved(self, product_id: int, location_id: Optional[int] = None) -> float:
        """
        Stock reserved = pending outbound moves in 'ready' status.
        """
        q = self.db.query(func.coalesce(func.sum(models.StockMove.quantity), 0.0)).filter(
            models.StockMove.product_id == product_id,
            models.StockMove.status == models.MoveStatus.ready,
            models.StockMove.move_type.in_([models.MoveType.delivery, models.MoveType.transfer]),
        )
        if location_id is not None:
            q = q.filter(models.StockMove.from_location_id == location_id)
        else:
            q = q.join(models.Location, models.StockMove.from_location_id == models.Location.id).filter(
                models.Location.is_virtual == False
            )
        return float(q.scalar() or 0.0)

    def get_free_to_use(self, product_id: int, location_id: Optional[int] = None) -> float:
        return max(0.0, self.get_on_hand(product_id, location_id) - self.get_reserved(product_id, location_id))

    def get_stock_overview(self, location_id: Optional[int] = None) -> List[schemas.StockItem]:
        products = self.db.query(models.Product).all()
        result = []
        for p in products:
            on_hand = self.get_on_hand(p.id, location_id)
            free = self.get_free_to_use(p.id, location_id)
            result.append(
                schemas.StockItem(
                    product_id=p.id,
                    product_name=p.name,
                    sku=p.sku,
                    cost_per_unit=p.cost_per_unit,
                    on_hand=on_hand,
                    free_to_use=free,
                    reorder_point=p.reorder_point,
                    low_stock=(on_hand <= p.reorder_point),
                )
            )
        return result
