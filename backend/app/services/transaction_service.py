import datetime
from sqlalchemy.orm import Session
from .. import models, ledger
from ..core import exceptions
from .inventory_service import InventoryService

class TransactionService:
    def __init__(self, db: Session):
        self.db = db
        self.inventory = InventoryService(db)

    def validate_receipt(self, move_id: int) -> models.StockMove:
        move = self.db.query(models.StockMove).get(move_id)
        if not move or move.move_type != models.MoveType.receipt:
            raise exceptions.NotFoundException("Receipt", move_id)
        if move.status == models.MoveStatus.done:
            raise exceptions.StockSenseException("Already validated", status_code=400)

        move.status = models.MoveStatus.done
        move.done_at = datetime.datetime.now(datetime.timezone.utc)
        self.db.commit()
        self.db.refresh(move)
        return move

    def validate_delivery(self, move_id: int) -> models.StockMove:
        move = self.db.query(models.StockMove).get(move_id)
        if not move or move.move_type != models.MoveType.delivery:
            raise exceptions.NotFoundException("Delivery", move_id)
        if move.status == models.MoveStatus.done:
            raise exceptions.StockSenseException("Already validated", status_code=400)
        if move.status == models.MoveStatus.cancelled:
            raise exceptions.StockSenseException("Cannot validate a cancelled delivery", status_code=400)

        available = self.inventory.get_on_hand(move.product_id, move.from_location_id)
        if available < move.quantity:
            move.status = models.MoveStatus.waiting
            self.db.commit()
            raise exceptions.InsufficientStockException(
                available=available,
                requested=move.quantity,
            )

        move.status = models.MoveStatus.done
        move.done_at = datetime.datetime.now(datetime.timezone.utc)
        self.db.commit()
        self.db.refresh(move)
        return move

    def validate_transfer(self, move_id: int) -> models.StockMove:
        move = self.db.query(models.StockMove).get(move_id)
        if not move or move.move_type != models.MoveType.transfer:
            raise exceptions.NotFoundException("Transfer", move_id)
        if move.status == models.MoveStatus.done:
            raise exceptions.StockSenseException("Already validated", status_code=400)

        available = self.inventory.get_on_hand(move.product_id, move.from_location_id)
        if available < move.quantity:
            move.status = models.MoveStatus.waiting
            self.db.commit()
            raise exceptions.StockSenseException(
                f"Insufficient stock at source. On hand: {available}, requested: {move.quantity}",
                status_code=400,
            )

        move.status = models.MoveStatus.done
        move.done_at = datetime.datetime.now(datetime.timezone.utc)
        self.db.commit()
        self.db.refresh(move)
        return move

    def create_adjustment(
        self,
        product_id: int,
        location_id: int,
        counted_quantity: float,
        contact: str,
        user_id: int,
    ) -> models.StockMove:
        location = self.db.query(models.Location).get(location_id)
        if not location:
            raise exceptions.StockSenseException("Invalid location", status_code=400)

        adj_virtual = ledger.get_or_create_virtual_location(self.db, "Inventory Adjustment", "ADJ")
        current = self.inventory.get_on_hand(product_id, location.id)
        diff = counted_quantity - current

        if diff == 0:
            raise exceptions.StockSenseException(
                "Counted quantity matches recorded stock - no adjustment needed", status_code=400
            )

        warehouse_code = location.warehouse.short_code if location.warehouse else "WH"
        reference = ledger.next_reference(self.db, warehouse_code, "ADJ")

        if diff > 0:
            from_loc_id, to_loc_id = adj_virtual.id, location.id
        else:
            from_loc_id, to_loc_id = location.id, adj_virtual.id

        move = models.StockMove(
            reference=reference,
            move_type=models.MoveType.adjustment,
            product_id=product_id,
            from_location_id=from_loc_id,
            to_location_id=to_loc_id,
            quantity=abs(diff),
            status=models.MoveStatus.done,
            contact=contact or "Stock Count",
            responsible_id=user_id,
            scheduled_date=datetime.datetime.now(datetime.timezone.utc),
            done_at=datetime.datetime.now(datetime.timezone.utc),
        )
        self.db.add(move)
        self.db.commit()
        self.db.refresh(move)
        return move
