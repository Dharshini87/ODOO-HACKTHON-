from decimal import Decimal
import datetime
import enum
from sqlalchemy import (
    Column,
    Integer,
    String,
    Numeric,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    CheckConstraint,
)
from sqlalchemy.orm import relationship
from ..db.base import Base


class TransactionType(str, enum.Enum):
    RECEIPT = "RECEIPT"
    DELIVERY = "DELIVERY"
    TRANSFER = "TRANSFER"
    ADJUSTMENT = "ADJUSTMENT"


class TransactionStatus(str, enum.Enum):
    DRAFT = "DRAFT"
    WAITING = "WAITING"
    READY = "READY"
    DONE = "DONE"
    CANCELED = "CANCELED"


class Transaction(Base):
    """
    ONE unified transaction model (Section 14).
    Types: RECEIPT, DELIVERY, TRANSFER, ADJUSTMENT
    States: DRAFT, WAITING, READY, DONE, CANCELED
    """
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True)
    reference = Column(String(100), unique=True, index=True, nullable=False)
    type = Column(Enum(TransactionType, name="transaction_type"), nullable=False, index=True)
    status = Column(
        Enum(TransactionStatus, name="transaction_status"),
        default=TransactionStatus.DRAFT,
        nullable=False,
        index=True,
    )
    source_location_id = Column(Integer, ForeignKey("locations.id", ondelete="RESTRICT"), nullable=True, index=True)
    destination_location_id = Column(Integer, ForeignKey("locations.id", ondelete="RESTRICT"), nullable=True, index=True)
    party_name = Column(String(255), nullable=True)
    contact = Column(String(255), nullable=True)
    delivery_address = Column(String(500), nullable=True)
    schedule_date = Column(DateTime(timezone=True), nullable=True)
    reason = Column(String(500), nullable=True)
    created_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    validated_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow, nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        default=datetime.datetime.utcnow,
        onupdate=datetime.datetime.utcnow,
        nullable=False,
    )
    validated_at = Column(DateTime(timezone=True), nullable=True)
    canceled_at = Column(DateTime(timezone=True), nullable=True)

    # Relationships
    source_location = relationship("Location", foreign_keys=[source_location_id])
    destination_location = relationship("Location", foreign_keys=[destination_location_id])
    creator = relationship("User", foreign_keys=[created_by])
    validator = relationship("User", foreign_keys=[validated_by])
    items = relationship("TransactionItem", back_populates="transaction", cascade="all, delete-orphan")
    ledger_entries = relationship("StockLedger", back_populates="transaction")

    __table_args__ = (
        CheckConstraint("type IN ('RECEIPT', 'DELIVERY', 'TRANSFER', 'ADJUSTMENT')", name="chk_valid_transaction_type"),
        CheckConstraint("status IN ('DRAFT', 'WAITING', 'READY', 'DONE', 'CANCELED')", name="chk_valid_transaction_status"),
        CheckConstraint(
            "(type != 'ADJUSTMENT') OR (reason IS NOT NULL AND LENGTH(TRIM(reason)) > 0)",
            name="chk_adjustment_reason_required",
        ),
    )


class TransactionItem(Base):
    """
    Transaction Items (Section 15).
    Normal transactions: quantity = movement quantity
    Adjustment: quantity = physical count, adjustment_delta = physical count - current stock
    """
    __tablename__ = "transaction_items"

    id = Column(Integer, primary_key=True, index=True)
    transaction_id = Column(Integer, ForeignKey("transactions.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
    quantity = Column(Numeric(12, 3), nullable=False)
    adjustment_delta = Column(Numeric(12, 3), nullable=True)

    transaction = relationship("Transaction", back_populates="items")
    product = relationship("Product", back_populates="transaction_items")

    __table_args__ = (
        CheckConstraint("quantity >= 0", name="chk_transaction_item_quantity_non_negative"),
    )


# ---------------------------------------------------------------------------
# Backward Compatibility layer for prototype routers during migration phases
# ---------------------------------------------------------------------------
class MoveType(str, enum.Enum):
    receipt = "receipt"
    delivery = "delivery"
    transfer = "transfer"
    adjustment = "adjustment"


class MoveStatus(str, enum.Enum):
    draft = "draft"
    waiting = "waiting"
    ready = "ready"
    done = "done"
    cancelled = "cancelled"


class StockMove(Base):
    __tablename__ = "stock_moves"

    id = Column(Integer, primary_key=True, index=True)
    reference = Column(String, unique=True, index=True, nullable=False)
    move_type = Column(Enum(MoveType), nullable=False)

    product_id = Column(Integer, ForeignKey("products.id"), nullable=False)
    from_location_id = Column(Integer, ForeignKey("locations.id"), nullable=True)
    to_location_id = Column(Integer, ForeignKey("locations.id"), nullable=True)

    quantity = Column(Float, nullable=False)
    status = Column(Enum(MoveStatus), default=MoveStatus.draft)

    contact = Column(String, nullable=True)
    responsible_id = Column(Integer, ForeignKey("users.id"), nullable=True)

    scheduled_date = Column(DateTime, default=datetime.datetime.utcnow)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    done_at = Column(DateTime, nullable=True)

    product = relationship("Product")
    from_location = relationship("Location", foreign_keys=[from_location_id])
    to_location = relationship("Location", foreign_keys=[to_location_id])
    responsible = relationship("User")
