import datetime
from decimal import Decimal
from sqlalchemy import Column, Integer, String, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from ..db.base import Base


class StockLedger(Base):
    """
    Stock Ledger (Section 7, Section 19, Section 24, Section 43).
    Immutable audit trail. Never delete historical ledger entries.
    Records:
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
    __tablename__ = "stock_ledger"

    id = Column(Integer, primary_key=True, index=True)
    transaction_id = Column(Integer, ForeignKey("transactions.id", ondelete="RESTRICT"), nullable=True, index=True)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
    location_id = Column(Integer, ForeignKey("locations.id", ondelete="RESTRICT"), nullable=False, index=True)
    quantity_before = Column(Numeric(12, 3), nullable=True)
    quantity_change = Column(Numeric(12, 3), nullable=False)
    quantity_after = Column(Numeric(12, 3), nullable=True)
    running_balance = Column(Numeric(12, 3), nullable=False)
    reference = Column(String(100), nullable=False, index=True)
    movement_type = Column(String(50), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow, nullable=False, index=True)
    created_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    transaction = relationship("Transaction", back_populates="ledger_entries")
    product = relationship("Product")
    location = relationship("Location")
    user = relationship("User", foreign_keys=[created_by])

    def get_quantity_after(self) -> Decimal:
        if self.quantity_after is not None:
            return Decimal(str(self.quantity_after))
        return Decimal(str(self.running_balance or 0.0))

    def get_quantity_before(self) -> Decimal:
        if self.quantity_before is not None:
            return Decimal(str(self.quantity_before))
        return self.get_quantity_after() - Decimal(str(self.quantity_change or 0.0))
