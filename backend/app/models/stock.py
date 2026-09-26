from decimal import Decimal
import datetime
from sqlalchemy import (
    Column,
    Integer,
    Numeric,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    CheckConstraint,
)
from sqlalchemy.orm import relationship
from ..db.base import Base


class Stock(Base):
    __tablename__ = "stock"

    id = Column(Integer, primary_key=True, index=True)
    product_id = Column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
    location_id = Column(Integer, ForeignKey("locations.id", ondelete="RESTRICT"), nullable=False, index=True)
    on_hand = Column(Numeric(12, 3), default=Decimal("0.000"), nullable=False)
    reserved = Column(Numeric(12, 3), default=Decimal("0.000"), nullable=False)
    version = Column(Integer, default=1, nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        default=datetime.datetime.utcnow,
        onupdate=datetime.datetime.utcnow,
        nullable=False,
    )

    product = relationship("Product", back_populates="stocks")
    location = relationship("Location", back_populates="stocks")

    __table_args__ = (
        UniqueConstraint("product_id", "location_id", name="uq_stock_product_location"),
        CheckConstraint("on_hand >= 0", name="chk_stock_on_hand_non_negative"),
        CheckConstraint("reserved >= 0", name="chk_stock_reserved_non_negative"),
        CheckConstraint("reserved <= on_hand", name="chk_stock_reserved_lte_on_hand"),
    )

    @property
    def free_to_use(self) -> Decimal:
        """
        CRITICAL SECTION 13 RULE:
        Do NOT store free_to_use in the database.
        Always calculate dynamically: free_to_use = on_hand - reserved
        """
        oh = Decimal(str(self.on_hand or 0.0))
        res = Decimal(str(self.reserved or 0.0))
        return oh - res
