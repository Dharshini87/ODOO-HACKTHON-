import datetime
from decimal import Decimal
from typing import Dict, Any, List, Optional
from sqlalchemy.orm import Session
from sqlalchemy import func
from .. import models, schemas


class IntelligenceService:
    def __init__(self, db: Session):
        self.db = db

    def _get_product_stock_and_outbound(self, product_id: int):
        """
        Helper to fetch live database stock and historical outbound consumption.
        Never fabricate predictions.
        """
        # Current stock across all locations
        stocks = self.db.query(models.Stock).filter(models.Stock.product_id == product_id).all()
        current_stock = float(sum(s.on_hand or Decimal("0.0") for s in stocks))

        # Check outbound transaction history from completed DELIVERIES
        tx_query = (
            self.db.query(
                models.TransactionItem.quantity,
                models.Transaction.created_at,
            )
            .join(models.Transaction, models.Transaction.id == models.TransactionItem.transaction_id)
            .filter(
                models.TransactionItem.product_id == product_id,
                models.Transaction.type == models.TransactionType.DELIVERY,
                models.Transaction.status == models.TransactionStatus.DONE,
            )
            .all()
        )

        # Also check ledger entries for any direct deliveries recorded
        ledger_query = (
            self.db.query(
                models.StockLedger.quantity_change,
                models.StockLedger.created_at,
            )
            .filter(
                models.StockLedger.product_id == product_id,
                models.StockLedger.movement_type.in_(["DELIVERY", "OUTBOUND"]),
            )
            .all()
        )

        total_qty = 0.0
        dates: List[datetime.datetime] = []

        if tx_query:
            for qty, dt in tx_query:
                total_qty += float(qty or 0.0)
                if dt:
                    dates.append(dt)
        elif ledger_query:
            for chg, dt in ledger_query:
                total_qty += abs(float(chg or 0.0))
                if dt:
                    dates.append(dt)

        return current_stock, total_qty, dates

    def get_stockout_predictions(self, product_id: Optional[int] = None) -> List[schemas.StockoutItem]:
        """
        GET /api/intelligence/stockout
        Section 28: Transparent stockout velocity and days to depletion calculations.
        If insufficient history exists: show "Not enough historical movement data."
        """
        query = self.db.query(models.Product).filter(models.Product.is_active == True)
        if product_id:
            query = query.filter(models.Product.id == product_id)
        products = query.all()

        results: List[schemas.StockoutItem] = []

        for p in products:
            current_stock, total_outbound, move_dates = self._get_product_stock_and_outbound(p.id)
            reorder_level = float(p.reorder_point or 0.0)

            # Rule: If insufficient history exists: show "Not enough historical movement data."
            if not move_dates or total_outbound <= 0.0:
                results.append(
                    schemas.StockoutItem(
                        product_id=p.id,
                        product_name=p.name,
                        sku=p.sku,
                        current_stock=current_stock,
                        average_daily_usage=None,
                        reorder_level=reorder_level,
                        estimated_days_to_reorder=None,
                        estimated_days_to_stockout=None,
                        has_sufficient_history=False,
                        message="Not enough historical movement data.",
                    )
                )
                continue

            # Calculate observed days window
            earliest = min(move_dates)
            days_span = max(1, (datetime.datetime.utcnow() - earliest).days)
            avg_daily_usage = round(total_outbound / days_span, 2)

            if avg_daily_usage <= 0:
                results.append(
                    schemas.StockoutItem(
                        product_id=p.id,
                        product_name=p.name,
                        sku=p.sku,
                        current_stock=current_stock,
                        average_daily_usage=0.0,
                        reorder_level=reorder_level,
                        estimated_days_to_reorder=None,
                        estimated_days_to_stockout=None,
                        has_sufficient_history=False,
                        message="Not enough historical movement data.",
                    )
                )
                continue

            # Transparent stockout calculation
            if current_stock <= 0:
                days_to_stockout = 0.0
                days_to_reorder = 0.0
            else:
                days_to_stockout = round(current_stock / avg_daily_usage, 1)
                if current_stock <= reorder_level:
                    days_to_reorder = 0.0
                else:
                    days_to_reorder = round((current_stock - reorder_level) / avg_daily_usage, 1)

            results.append(
                schemas.StockoutItem(
                    product_id=p.id,
                    product_name=p.name,
                    sku=p.sku,
                    current_stock=current_stock,
                    average_daily_usage=avg_daily_usage,
                    reorder_level=reorder_level,
                    estimated_days_to_reorder=days_to_reorder,
                    estimated_days_to_stockout=days_to_stockout,
                    has_sufficient_history=True,
                    message=None,
                )
            )

        return results

    def get_reorder_recommendations(
        self, target_coverage: int = 30, product_id: Optional[int] = None
    ) -> List[schemas.ReorderItem]:
        """
        GET /api/intelligence/reorder
        Section 28: Transparent reorder recommendations with clear calculation explanations.
        """
        query = self.db.query(models.Product).filter(models.Product.is_active == True)
        if product_id:
            query = query.filter(models.Product.id == product_id)
        products = query.all()

        results: List[schemas.ReorderItem] = []

        for p in products:
            current_stock, total_outbound, move_dates = self._get_product_stock_and_outbound(p.id)
            reorder_level = float(p.reorder_point or 0.0)

            if not move_dates or total_outbound <= 0.0:
                # If insufficient history exists
                explanation = (
                    f"Not enough historical movement data to compute reliable consumption rate. "
                    f"Current stock is {current_stock} units with a configured reorder level of {reorder_level} units."
                )
                results.append(
                    schemas.ReorderItem(
                        product_id=p.id,
                        product_name=p.name,
                        sku=p.sku,
                        current_stock=current_stock,
                        average_usage=None,
                        target_coverage=target_coverage,
                        recommended_reorder_quantity=max(0.0, reorder_level - current_stock),
                        explanation=explanation,
                        has_sufficient_history=False,
                        message="Not enough historical movement data.",
                    )
                )
                continue

            earliest = min(move_dates)
            days_span = max(1, (datetime.datetime.utcnow() - earliest).days)
            avg_daily_usage = round(total_outbound / days_span, 2)

            if avg_daily_usage <= 0:
                explanation = "Zero outbound usage detected in observed period."
                results.append(
                    schemas.ReorderItem(
                        product_id=p.id,
                        product_name=p.name,
                        sku=p.sku,
                        current_stock=current_stock,
                        average_usage=0.0,
                        target_coverage=target_coverage,
                        recommended_reorder_quantity=0.0,
                        explanation=explanation,
                        has_sufficient_history=False,
                        message="Not enough historical movement data.",
                    )
                )
                continue

            # Transparent arithmetic:
            # Target Need = (Average Usage * Target Coverage) + Safety Reorder Level
            # Recommended Order = max(0, Target Need - Current Stock)
            target_need = round((avg_daily_usage * target_coverage) + reorder_level, 1)
            deficit = target_need - current_stock
            reorder_qty = max(0.0, round(deficit, 1))

            explanation = (
                f"Formula: Target Need = (Avg Usage: {avg_daily_usage}/day × Coverage: {target_coverage} days) "
                f"+ Buffer: {reorder_level} = {target_need} units. "
                f"Deficit = {target_need} - Current Stock ({current_stock}) = {reorder_qty} units recommended."
            )

            results.append(
                schemas.ReorderItem(
                    product_id=p.id,
                    product_name=p.name,
                    sku=p.sku,
                    current_stock=current_stock,
                    average_usage=avg_daily_usage,
                    target_coverage=target_coverage,
                    recommended_reorder_quantity=reorder_qty,
                    explanation=explanation,
                    has_sufficient_history=True,
                    message=None,
                )
            )

        return results
