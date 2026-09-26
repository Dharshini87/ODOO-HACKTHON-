import functools
import json
import datetime
import threading
from decimal import Decimal
from typing import Optional, List, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import text

from .. import models
from ..core.exceptions import StockSenseException, InsufficientStockException, NotFoundException
from ..models.transaction import TransactionStatus, TransactionType


def locked_engine_action(func):
    """
    Ensures thread-safe serialized execution of inventory mutation transactions.
    """
    @functools.wraps(func)
    def wrapper(self, *args, **kwargs):
        with InventoryTransactionEngine._lock:
            return func(self, *args, **kwargs)
    return wrapper


class InventoryTransactionEngine:
    """
    Section 18: Authoritative Inventory Transaction Engine.
    ALL inventory mutations occur in backend database transactions.
    Never perform inventory mutation directly inside Flutter.
    """
    _lock = threading.RLock()

    def __init__(self, db: Session):
        self.db = db

    def check_or_store_idempotency(
        self,
        key: Optional[str],
        endpoint: str,
        user_id: Optional[int],
    ) -> Optional[models.IdempotencyKey]:
        """
        Section 40: Check if request has already been executed.
        A transaction must never mutate inventory twice.
        Unique: key + endpoint + user
        """
        if not key:
            return None

        clean_key = key.strip()
        existing = (
            self.db.query(models.IdempotencyKey)
            .filter(
                models.IdempotencyKey.key == clean_key,
                models.IdempotencyKey.endpoint == endpoint,
                models.IdempotencyKey.user_id == user_id,
            )
            .first()
        )
        return existing

    def record_idempotency(
        self,
        key: Optional[str],
        endpoint: str,
        user_id: Optional[int],
        response_code: int,
        response_body: dict,
    ) -> None:
        if not key:
            return
        clean_key = key.strip()
        rec = models.IdempotencyKey(
            key=clean_key,
            endpoint=endpoint,
            user_id=user_id,
            response_code=response_code,
            response_body=json.dumps(response_body),
            expires_at=datetime.datetime.utcnow() + datetime.timedelta(days=7),
        )
        self.db.add(rec)

    def _get_or_create_locked_stock(
        self,
        product_id: int,
        location_id: int,
    ) -> models.Stock:
        """
        Locks stock row using SELECT FOR UPDATE.
        Handles stock row creation race condition safely.
        """
        # Try locking existing
        bind = self.db.get_bind()
        is_sqlite = "sqlite" in bind.dialect.name.lower()

        q = self.db.query(models.Stock).filter(
            models.Stock.product_id == product_id,
            models.Stock.location_id == location_id,
        )
        if not is_sqlite:
            q = q.with_for_update()
        stock = q.first()

        if stock is None:
            # Creation race safe insert
            stock = models.Stock(
                product_id=product_id,
                location_id=location_id,
                on_hand=Decimal("0.000"),
                reserved=Decimal("0.000"),
                version=1,
            )
            self.db.add(stock)
            self.db.flush()

            # Now re-lock the newly created row
            q = self.db.query(models.Stock).filter(models.Stock.id == stock.id)
            if not is_sqlite:
                q = q.with_for_update()
            stock = q.first()

        return stock

    def check_waiting_deliveries(self) -> List[models.Transaction]:
        """
        Section 21: WAITING -> READY
        Do NOT use Redis, Celery, or a background worker for MVP.

        When a receipt or other stock-increasing transaction completes:
        1. Increase inventory (already done before calling this).
        2. Find WAITING deliveries.
        3. Process oldest-created-first.
        4. Check all products.
        5. If ALL products are available:
           - reserve stock
           - change WAITING -> READY
        6. Otherwise leave WAITING.

        No partial fulfillment.
        A multi-product delivery becomes READY only when ALL products are available.
        """
        bind = self.db.get_bind()
        is_sqlite = "sqlite" in bind.dialect.name.lower()

        # 2 & 3: Find WAITING deliveries, oldest-created-first
        q = (
            self.db.query(models.Transaction)
            .filter(
                models.Transaction.type == TransactionType.DELIVERY,
                models.Transaction.status == TransactionStatus.WAITING,
            )
            .order_by(models.Transaction.created_at.asc(), models.Transaction.id.asc())
        )
        if not is_sqlite:
            q = q.with_for_update()
        waiting_deliveries = q.all()

        transitioned = []
        for delivery in waiting_deliveries:
            sorted_items = sorted(delivery.items, key=lambda it: (it.product_id, delivery.source_location_id or 0))
            if not sorted_items:
                continue

            all_available = True
            for item in sorted_items:
                stock = self._get_or_create_locked_stock(item.product_id, delivery.source_location_id)
                needed = Decimal(str(item.quantity))
                if stock.free_to_use < needed:
                    all_available = False
                    break

            if all_available:
                for item in sorted_items:
                    stock = self._get_or_create_locked_stock(item.product_id, delivery.source_location_id)
                    needed = Decimal(str(item.quantity))
                    stock.reserved = stock.reserved + needed
                    stock.version += 1
                delivery.status = TransactionStatus.READY
                transitioned.append(delivery)

        if transitioned:
            self.db.flush()

        return transitioned

    @locked_engine_action
    def prepare_delivery(self, transaction_id: int, user: models.User) -> models.Transaction:
        """
        Section 16, 17, 20:
        DRAFT DELIVERY ->
          insufficient stock -> WAITING (no reservation, no stock impact)
          stock available -> READY (reserve quantity: stock.reserved += qty)
        """
        try:
            bind = self.db.get_bind()
            is_sqlite = "sqlite" in bind.dialect.name.lower()

            q = self.db.query(models.Transaction).filter(models.Transaction.id == transaction_id)
            if not is_sqlite:
                q = q.with_for_update()
            tx = q.first()

            if not tx:
                raise NotFoundException("Transaction", transaction_id)
            if tx.type != TransactionType.DELIVERY:
                raise StockSenseException("Only DELIVERY transactions can be prepared/reserved", status_code=400)
            if tx.status not in (TransactionStatus.DRAFT, TransactionStatus.WAITING):
                raise StockSenseException(f"Cannot prepare delivery in status {tx.status}", status_code=400)

            # Lock stock rows in deterministic order
            sorted_items = sorted(tx.items, key=lambda it: (it.product_id, tx.source_location_id or 0))

            all_available = True
            for item in sorted_items:
                stock = self._get_or_create_locked_stock(item.product_id, tx.source_location_id)
                needed = Decimal(str(item.quantity))
                if stock.free_to_use < needed:
                    all_available = False
                    break

            if all_available and sorted_items:
                # Transition to READY & reserve
                for item in sorted_items:
                    stock = self._get_or_create_locked_stock(item.product_id, tx.source_location_id)
                    needed = Decimal(str(item.quantity))
                    stock.reserved = stock.reserved + needed
                    stock.version += 1
                tx.status = TransactionStatus.READY
            else:
                # Insufficient stock -> WAITING
                tx.status = TransactionStatus.WAITING

            self.db.commit()
            self.db.refresh(tx)
            return tx
        except Exception:
            self.db.rollback()
            raise

    @locked_engine_action
    def cancel_transaction(self, transaction_id: int, user: models.User) -> models.Transaction:
        """
        Section 16 & 17:
        DRAFT -> CANCELED
        WAITING -> CANCELED
        READY -> CANCELED (release reservation; do not change on_hand)
        DONE is immutable!
        """
        try:
            bind = self.db.get_bind()
            is_sqlite = "sqlite" in bind.dialect.name.lower()

            q = self.db.query(models.Transaction).filter(models.Transaction.id == transaction_id)
            if not is_sqlite:
                q = q.with_for_update()
            tx = q.first()

            if not tx:
                raise NotFoundException("Transaction", transaction_id)

            if tx.status == TransactionStatus.DONE:
                raise StockSenseException("DONE transactions are immutable and cannot be canceled", status_code=400)
            if tx.status == TransactionStatus.CANCELED:
                return tx

            # If canceling a READY delivery, release reserved quantities
            if tx.status == TransactionStatus.READY and tx.type == TransactionType.DELIVERY:
                sorted_items = sorted(tx.items, key=lambda it: (it.product_id, tx.source_location_id or 0))
                for item in sorted_items:
                    stock = self._get_or_create_locked_stock(item.product_id, tx.source_location_id)
                    qty = Decimal(str(item.quantity))
                    stock.reserved = max(Decimal("0.000"), stock.reserved - qty)
                    stock.version += 1
                self.check_waiting_deliveries()

            tx.status = TransactionStatus.CANCELED
            tx.canceled_at = datetime.datetime.utcnow()
            self.db.commit()
            self.db.refresh(tx)
            return tx
        except Exception:
            self.db.rollback()
            raise

    @locked_engine_action
    def validate_transaction(
        self,
        transaction_id: int,
        user: models.User,
        idempotency_key: Optional[str] = None,
    ) -> models.Transaction:
        """
        Section 18 13-STEP INVENTORY TRANSACTION ENGINE:

        BEGIN TRANSACTION
        1. Lock transaction.
        2. Lock affected stock rows.
        3. Lock rows in deterministic order.
        4. Validate transaction status.
        5. Validate products.
        6. Validate locations.
        7. Validate quantities.
        8. Validate available stock.
        9. Apply stock changes.
        10. Apply reservations.
        11. Write ledger entries.
        12. Update transaction.
        13. COMMIT.

        On any failure: ROLLBACK EVERYTHING.
        """
        endpoint = f"/api/transactions/{transaction_id}/validate"

        # Check idempotency first (Section 40)
        idemp = self.check_or_store_idempotency(idempotency_key, endpoint, user.id)
        if idemp and idemp.response_code == 200 and idemp.response_body:
            # Return idempotent response
            tx = self.db.query(models.Transaction).filter(models.Transaction.id == transaction_id).first()
            if tx:
                return tx

        bind = self.db.get_bind()
        is_sqlite = "sqlite" in bind.dialect.name.lower()

        try:
            # 1. Lock transaction
            q = self.db.query(models.Transaction).filter(models.Transaction.id == transaction_id)
            if not is_sqlite:
                q = q.with_for_update()
            tx = q.first()

            if not tx:
                raise NotFoundException("Transaction", transaction_id)

            # 4. Validate transaction status
            if tx.status == TransactionStatus.DONE:
                raise StockSenseException("Transaction is already DONE and immutable", status_code=400)
            if tx.status == TransactionStatus.CANCELED:
                raise StockSenseException("Cannot validate a CANCELED transaction", status_code=400)

            if not tx.items:
                raise StockSenseException("Transaction contains no items to validate", status_code=400)

            # 5. Validate products & 6. Validate locations & 7. Validate quantities
            affected_pairs: List[Tuple[int, int]] = []
            for item in tx.items:
                if not item.product or not item.product.is_active:
                    raise StockSenseException(f"Product id {item.product_id} is inactive or invalid", status_code=400)

                qty = Decimal(str(item.quantity))
                if tx.type != TransactionType.ADJUSTMENT and qty <= 0:
                    raise StockSenseException(f"Invalid quantity {qty}. Must be > 0", status_code=400)

                if tx.type == TransactionType.RECEIPT:
                    if not tx.destination_location_id:
                        raise StockSenseException("Receipt requires destination_location_id", status_code=400)
                    affected_pairs.append((item.product_id, tx.destination_location_id))

                elif tx.type == TransactionType.DELIVERY:
                    if not tx.source_location_id:
                        raise StockSenseException("Delivery requires source_location_id", status_code=400)
                    affected_pairs.append((item.product_id, tx.source_location_id))

                elif tx.type == TransactionType.TRANSFER:
                    if not tx.source_location_id or not tx.destination_location_id:
                        raise StockSenseException("Transfer requires both source and destination locations", status_code=400)
                    if tx.source_location_id == tx.destination_location_id:
                        raise StockSenseException("Source and destination locations cannot be identical", status_code=400)
                    affected_pairs.append((item.product_id, tx.source_location_id))
                    affected_pairs.append((item.product_id, tx.destination_location_id))

                elif tx.type == TransactionType.ADJUSTMENT:
                    loc_id = tx.source_location_id or tx.destination_location_id
                    if not loc_id:
                        raise StockSenseException("Adjustment requires a location", status_code=400)
                    if not tx.reason or not tx.reason.strip():
                        raise StockSenseException("Adjustment reason is required (Section 42)", status_code=400)
                    affected_pairs.append((item.product_id, loc_id))

            # 2. Lock affected stock rows
            # 3. Lock rows in DETERMINISTIC ORDER to prevent deadlocks (sorted by (product_id, location_id))
            unique_pairs = sorted(list(set(affected_pairs)), key=lambda x: (x[0], x[1]))
            locked_stocks = {}
            for p_id, l_id in unique_pairs:
                locked_stocks[(p_id, l_id)] = self._get_or_create_locked_stock(p_id, l_id)

            # 8. Validate available stock / free_to_use (Step 8 of 13)
            # Multi-product operations must be all-or-nothing
            for item in tx.items:
                qty = Decimal(str(item.quantity))

                if tx.type == TransactionType.DELIVERY:
                    stock = locked_stocks[(item.product_id, tx.source_location_id)]
                    if tx.status != TransactionStatus.READY:
                        if stock.free_to_use < qty:
                            raise InsufficientStockException(
                                available=float(stock.free_to_use),
                                requested=float(qty),
                            )
                elif tx.type == TransactionType.TRANSFER:
                    src_stock = locked_stocks[(item.product_id, tx.source_location_id)]
                    if src_stock.free_to_use < qty:
                        raise InsufficientStockException(
                            available=float(src_stock.free_to_use),
                            requested=float(qty),
                        )
                elif tx.type == TransactionType.ADJUSTMENT:
                    loc_id = tx.source_location_id or tx.destination_location_id
                    stock = locked_stocks[(item.product_id, loc_id)]
                    physical_count = qty
                    # Section 42: Adjustment cannot reduce below reserved
                    if physical_count < stock.reserved:
                        raise StockSenseException(
                            f"Adjustment cannot reduce stock below reserved quantity ({stock.reserved})",
                            status_code=400,
                        )

            # 9. Apply stock changes & 10. Apply reservations & 11. Write ledger
            now = datetime.datetime.utcnow()

            for item in tx.items:
                qty = Decimal(str(item.quantity))

                if tx.type == TransactionType.RECEIPT:
                    stock = locked_stocks[(item.product_id, tx.destination_location_id)]
                    stock.on_hand = stock.on_hand + qty
                    stock.version += 1

                    # 11. Write ledger entry
                    ledger_entry = models.StockLedger(
                        transaction_id=tx.id,
                        product_id=item.product_id,
                        location_id=tx.destination_location_id,
                        quantity_before=stock.on_hand - qty,
                        quantity_change=qty,
                        quantity_after=stock.on_hand,
                        running_balance=stock.on_hand,
                        reference=tx.reference,
                        movement_type="RECEIPT",
                        created_by=user.id,
                        created_at=now,
                    )
                    self.db.add(ledger_entry)

                elif tx.type == TransactionType.DELIVERY:
                    stock = locked_stocks[(item.product_id, tx.source_location_id)]

                    # If coming from READY, reservation is already held
                    if tx.status == TransactionStatus.READY:
                        stock.on_hand = stock.on_hand - qty
                        stock.reserved = max(Decimal("0.000"), stock.reserved - qty)
                    else:
                        stock.on_hand = stock.on_hand - qty

                    stock.version += 1

                    # 11. Write ledger entry
                    ledger_entry = models.StockLedger(
                        transaction_id=tx.id,
                        product_id=item.product_id,
                        location_id=tx.source_location_id,
                        quantity_before=stock.on_hand + qty,
                        quantity_change=-qty,
                        quantity_after=stock.on_hand,
                        running_balance=stock.on_hand,
                        reference=tx.reference,
                        movement_type="DELIVERY",
                        created_by=user.id,
                        created_at=now,
                    )
                    self.db.add(ledger_entry)

                elif tx.type == TransactionType.TRANSFER:
                    src_stock = locked_stocks[(item.product_id, tx.source_location_id)]
                    dst_stock = locked_stocks[(item.product_id, tx.destination_location_id)]

                    src_stock.on_hand = src_stock.on_hand - qty
                    src_stock.version += 1

                    dst_stock.on_hand = dst_stock.on_hand + qty
                    dst_stock.version += 1

                    # Outflow ledger
                    self.db.add(models.StockLedger(
                        transaction_id=tx.id,
                        product_id=item.product_id,
                        location_id=tx.source_location_id,
                        quantity_before=src_stock.on_hand + qty,
                        quantity_change=-qty,
                        quantity_after=src_stock.on_hand,
                        running_balance=src_stock.on_hand,
                        reference=tx.reference,
                        movement_type="TRANSFER_OUT",
                        created_by=user.id,
                        created_at=now,
                    ))

                    # Inflow ledger
                    self.db.add(models.StockLedger(
                        transaction_id=tx.id,
                        product_id=item.product_id,
                        location_id=tx.destination_location_id,
                        quantity_before=dst_stock.on_hand - qty,
                        quantity_change=qty,
                        quantity_after=dst_stock.on_hand,
                        running_balance=dst_stock.on_hand,
                        reference=tx.reference,
                        movement_type="TRANSFER_IN",
                        created_by=user.id,
                        created_at=now,
                    ))

                elif tx.type == TransactionType.ADJUSTMENT:
                    loc_id = tx.source_location_id or tx.destination_location_id
                    stock = locked_stocks[(item.product_id, loc_id)]

                    # Physical count
                    physical_count = qty
                    delta = physical_count - stock.on_hand
                    item.adjustment_delta = delta
                    stock.on_hand = physical_count
                    stock.version += 1

                    self.db.add(models.StockLedger(
                        transaction_id=tx.id,
                        product_id=item.product_id,
                        location_id=loc_id,
                        quantity_before=stock.on_hand - delta,
                        quantity_change=delta,
                        quantity_after=stock.on_hand,
                        running_balance=stock.on_hand,
                        reference=tx.reference,
                        movement_type="ADJUSTMENT",
                        created_by=user.id,
                        created_at=now,
                    ))

            # 12. Update transaction
            tx.status = TransactionStatus.DONE
            tx.validated_by = user.id
            tx.validated_at = now

            # Record Idempotency key (Section 40)
            if idempotency_key:
                self.record_idempotency(
                    key=idempotency_key,
                    endpoint=endpoint,
                    user_id=user.id,
                    response_code=200,
                    response_body={"id": tx.id, "reference": tx.reference, "status": "DONE"},
                )

            # Section 21: When a receipt or other stock-increasing transaction completes:
            # 1. Increase inventory (completed above)
            # 2. Find WAITING deliveries
            # 3. Process oldest-created-first
            # 4. Check all products
            # 5. If ALL products are available: reserve stock & change WAITING -> READY
            # 6. Otherwise leave WAITING
            if tx.type in (TransactionType.RECEIPT, TransactionType.ADJUSTMENT, TransactionType.TRANSFER):
                self.check_waiting_deliveries()

            # 13. COMMIT
            self.db.commit()
            self.db.refresh(tx)
            return tx

        except Exception:
            # On any failure: ROLLBACK EVERYTHING
            self.db.rollback()
            raise
