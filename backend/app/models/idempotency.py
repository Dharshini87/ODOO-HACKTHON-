import datetime
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship
from ..db.base import Base


class IdempotencyKey(Base):
    """
    Idempotency Keys (Section 7, Section 40).
    Guarantees safe execution of inventory transactions.
    A transaction must never mutate inventory twice.
    Unique constraint: key + endpoint + user
    """
    __tablename__ = "idempotency_keys"

    id = Column(Integer, primary_key=True, index=True)
    key = Column(String(255), index=True, nullable=False)
    endpoint = Column(String(255), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    request_hash = Column(String(255), nullable=True)
    response_code = Column(Integer, nullable=True)
    response_body = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=True)

    user = relationship("User")

    __table_args__ = (
        UniqueConstraint("key", "endpoint", "user_id", name="uq_idempotency_key_endpoint_user"),
    )
