from decimal import Decimal
import datetime
from typing import List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import func
from .. import models, schemas


class DashboardService:
    def __init__(self, db: Session):
        self.db = db

    def get_dashboard_summary(self) -> schemas.DashboardSummaryOut:
        """
        Database-driven dashboard calculation fulfilling Section 26 and Section 27.
        Never hardcode dashboard numbers.
        """
        products = self.db.query(models.Product).filter(models.Product.is_active == True).all()

        total_stock = Decimal("0.0")
        low_stock_count = 0
        out_of_stock_count = 0
        low_stock_items: List[schemas.LowStockProductItem] = []
        total_valuation = Decimal("0.0")

        # Map stocks by product_id
        stocks = self.db.query(models.Stock).all()
        stock_by_product: Dict[int, Dict[str, Decimal]] = {}
        for s in stocks:
            pid = s.product_id
            if pid not in stock_by_product:
                stock_by_product[pid] = {"on_hand": Decimal("0.0"), "reserved": Decimal("0.0")}
            stock_by_product[pid]["on_hand"] += Decimal(str(s.on_hand or 0.0))
            stock_by_product[pid]["reserved"] += Decimal(str(s.reserved or 0.0))

        for p in products:
            p_stock = stock_by_product.get(p.id, {"on_hand": Decimal("0.0"), "reserved": Decimal("0.0")})
            on_hand = p_stock["on_hand"]
            reserved = p_stock["reserved"]
            free_to_use = on_hand - reserved
            reorder_level = Decimal(str(p.reorder_point or 0.0))
            unit_cost = Decimal(str(p.cost_per_unit or 0.0))

            total_stock += on_hand
            total_valuation += on_hand * unit_cost

            # Section 27 Low Stock Rules
            # if on_hand == 0: OUT OF STOCK
            # elif on_hand <= reorder_level: LOW STOCK
            # else: NORMAL
            if on_hand == Decimal("0.0"):
                status = "OUT OF STOCK"
                out_of_stock_count += 1
            elif on_hand <= reorder_level:
                status = "LOW STOCK"
                low_stock_count += 1
            else:
                status = "NORMAL"

            category_name = p.category.name if p.category else None

            item = schemas.LowStockProductItem(
                product_id=p.id,
                product_name=p.name,
                sku=p.sku,
                category_name=category_name,
                unit_of_measure=p.unit_of_measure or "unit",
                cost_per_unit=float(unit_cost),
                on_hand=float(on_hand),
                reserved=float(reserved),
                free_to_use=float(free_to_use),
                reorder_level=float(reorder_level),
                status=status,
            )

            if status in ("OUT OF STOCK", "LOW STOCK"):
                low_stock_items.append(item)

        # Sort low stock items: OUT OF STOCK first, then lowest on_hand
        low_stock_items.sort(key=lambda x: (0 if x.status == "OUT OF STOCK" else 1, x.on_hand))

        # Operation Metrics: query unified Transaction model (fallback to StockMove if any)
        pending_statuses = [
            models.TransactionStatus.DRAFT,
            models.TransactionStatus.WAITING,
            models.TransactionStatus.READY,
        ]

        # Receipts
        pending_receipts = self.db.query(models.Transaction).filter(
            models.Transaction.type == models.TransactionType.RECEIPT,
            models.Transaction.status.in_(pending_statuses),
        ).count()

        # Deliveries
        pending_deliveries = self.db.query(models.Transaction).filter(
            models.Transaction.type == models.TransactionType.DELIVERY,
            models.Transaction.status.in_(pending_statuses),
        ).count()

        # Section 26 Waiting Deliveries
        waiting_deliveries = self.db.query(models.Transaction).filter(
            models.Transaction.type == models.TransactionType.DELIVERY,
            models.Transaction.status == models.TransactionStatus.WAITING,
        ).count()

        # Transfers Scheduled
        transfers_scheduled = self.db.query(models.Transaction).filter(
            models.Transaction.type == models.TransactionType.TRANSFER,
            models.Transaction.status.in_(pending_statuses),
        ).count()

        # Recent Movements (Top 10)
        recent_txs = (
            self.db.query(models.Transaction)
            .order_by(models.Transaction.created_at.desc())
            .limit(10)
            .all()
        )

        recent_movements: List[schemas.RecentMovementItem] = []
        for tx in recent_txs:
            first_item = tx.items[0] if tx.items else None
            prod_name = first_item.product.name if first_item and first_item.product else "Multiple Items"
            sku = first_item.product.sku if first_item and first_item.product else "-"
            qty = float(sum(it.quantity for it in tx.items)) if tx.items else 0.0

            src = tx.source_location.name if tx.source_location else None
            dest = tx.destination_location.name if tx.destination_location else None

            recent_movements.append(
                schemas.RecentMovementItem(
                    id=tx.id,
                    reference=tx.reference,
                    type=tx.type.value if hasattr(tx.type, "value") else str(tx.type),
                    status=tx.status.value if hasattr(tx.status, "value") else str(tx.status),
                    product_name=prod_name,
                    sku=sku,
                    quantity=qty,
                    from_location=src,
                    to_location=dest,
                    created_at=tx.created_at,
                )
            )

        # Inventory Intelligence Preview
        # Fast moving products based on completed deliveries
        fast_moving_query = (
            self.db.query(
                models.TransactionItem.product_id,
                func.sum(models.TransactionItem.quantity).label("total_out"),
            )
            .join(models.Transaction, models.Transaction.id == models.TransactionItem.transaction_id)
            .filter(
                models.Transaction.type == models.TransactionType.DELIVERY,
                models.Transaction.status == models.TransactionStatus.DONE,
            )
            .group_by(models.TransactionItem.product_id)
            .order_by(func.sum(models.TransactionItem.quantity).desc())
            .limit(3)
            .all()
        )

        fast_moving_names = []
        for pid, _ in fast_moving_query:
            p = self.db.query(models.Product).filter(models.Product.id == pid).first()
            if p:
                fast_moving_names.append(p.name)

        # Dead stock: Products with stock > 0 but no DONE transactions in the last 30 days
        thirty_days_ago = datetime.datetime.utcnow() - datetime.timedelta(days=30)
        active_product_ids = {
            row[0]
            for row in self.db.query(models.TransactionItem.product_id)
            .join(models.Transaction, models.Transaction.id == models.TransactionItem.transaction_id)
            .filter(
                models.Transaction.status == models.TransactionStatus.DONE,
                models.Transaction.created_at >= thirty_days_ago,
            )
            .distinct()
            .all()
        }

        dead_stock_count = sum(
            1
            for p in products
            if p.id not in active_product_ids
            and stock_by_product.get(p.id, {}).get("on_hand", Decimal("0.0")) > Decimal("0.0")
        )

        intelligence = schemas.IntelligencePreview(
            total_stock_value=float(total_valuation),
            fast_moving_items=fast_moving_names,
            dead_stock_count=dead_stock_count,
            reorder_recommended_count=low_stock_count + out_of_stock_count,
            top_moving_product=fast_moving_names[0] if fast_moving_names else None,
        )

        return schemas.DashboardSummaryOut(
            total_stock=float(total_stock),
            low_stock=low_stock_count,
            out_of_stock=out_of_stock_count,
            pending_receipts=pending_receipts,
            pending_deliveries=pending_deliveries,
            waiting_deliveries=waiting_deliveries,
            transfers_scheduled=transfers_scheduled,
            total_products=len(products),
            low_stock_count=low_stock_count,
            out_of_stock_count=out_of_stock_count,
            low_stock_products=low_stock_items,
            recent_movements=recent_movements,
            intelligence_preview=intelligence,
        )
