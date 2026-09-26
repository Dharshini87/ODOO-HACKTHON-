from decimal import Decimal
import datetime
from sqlalchemy import Column, Integer, String, Numeric, Boolean, DateTime, ForeignKey, CheckConstraint
from sqlalchemy.orm import relationship, synonym
from ..db.base import Base


class Product(Base):
    __tablename__ = "products"
    __table_args__ = (
        CheckConstraint("reorder_point >= 0", name="chk_product_reorder_level_non_negative"),
    )

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    sku = Column(String(100), unique=True, index=True, nullable=False)
    category_id = Column(Integer, ForeignKey("categories.id", ondelete="RESTRICT"), nullable=True)
    unit_of_measure = Column(String(50), default="unit", nullable=False)
    cost_per_unit = Column(Numeric(12, 2), default=Decimal("0.00"), nullable=False)
    reorder_point = Column(Numeric(12, 3), default=Decimal("0.000"), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)

    unit_cost = synonym("cost_per_unit")
    reorder_level = synonym("reorder_point")

    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow, nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        default=datetime.datetime.utcnow,
        onupdate=datetime.datetime.utcnow,
        nullable=False,
    )

    category = relationship("Category", back_populates="products")
    stocks = relationship("Stock", back_populates="product", cascade="all, delete-orphan")
    transaction_items = relationship("TransactionItem", back_populates="product")
