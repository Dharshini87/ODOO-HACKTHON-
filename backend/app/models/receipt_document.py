import datetime
import json
from decimal import Decimal
from typing import Optional, Dict, Any
from sqlalchemy import Column, Integer, String, Text, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import relationship

from ..db.base import Base


class ReceiptDocument(Base):
    """
    Receipt Document & OCR Verification Record (Sections 38, 39, 42).
    Tracks physical supplier receipt documents uploaded for assistive verification.
    NEVER mutates inventory or creates ledger entries directly.
    """
    __tablename__ = "receipt_documents"

    id = Column(Integer, primary_key=True, index=True)
    transaction_id = Column(Integer, ForeignKey("transactions.id", ondelete="CASCADE"), nullable=False, index=True)
    original_filename = Column(String(255), nullable=False)
    storage_key = Column(String(255), nullable=False, unique=True, index=True)
    mime_type = Column(String(100), nullable=False)
    file_size = Column(Integer, nullable=False)
    page_count = Column(Integer, default=1, nullable=False)
    
    # Status: UPLOADED, PROCESSING, COMPLETED, REVIEW_REQUIRED, FAILED
    ocr_status = Column(String(50), default="UPLOADED", nullable=False, index=True)
    ocr_confidence = Column(Numeric(5, 4), nullable=True)
    
    # Structured JSON payloads
    extracted_data_json = Column(Text, nullable=True)
    verification_result_json = Column(Text, nullable=True)
    
    uploaded_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    uploaded_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow, nullable=False)
    processed_at = Column(DateTime(timezone=True), nullable=True)

    # Relationships
    transaction = relationship("Transaction", backref="documents")
    uploader = relationship("User", foreign_keys=[uploaded_by])

    @property
    def extracted_data(self) -> Optional[Dict[str, Any]]:
        if self.extracted_data_json:
            try:
                return json.loads(self.extracted_data_json)
            except Exception:
                return None
        return None

    @extracted_data.setter
    def extracted_data(self, val: Optional[Dict[str, Any]]):
        if val is not None:
            self.extracted_data_json = json.dumps(val, default=str)
        else:
            self.extracted_data_json = None

    @property
    def verification_result(self) -> Optional[Dict[str, Any]]:
        if self.verification_result_json:
            try:
                return json.loads(self.verification_result_json)
            except Exception:
                return None
        return None

    @verification_result.setter
    def verification_result(self, val: Optional[Dict[str, Any]]):
        if val is not None:
            self.verification_result_json = json.dumps(val, default=str)
        else:
            self.verification_result_json = None
