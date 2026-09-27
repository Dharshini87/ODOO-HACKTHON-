"""
Secure password reset OTP model.

Security invariants (enforced at this layer and at the service layer):
- otp_hash: SHA-256 hex-digest of the 6-digit OTP — NEVER plaintext.
- expires_at: 10-minute TTL.
- attempts: max 5 failed attempts before record is locked.
- is_used: single-use; True after a successful reset or when superseded.
- last_resend_at: used for 60-second resend cooldown.
"""
import datetime
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from ..db.base import Base


class PasswordResetOtp(Base):
    __tablename__ = "password_reset_otps"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # SHA-256 hex digest (64 hex chars) — never store raw OTP
    otp_hash = Column(String(64), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    attempts = Column(Integer, nullable=False, default=0)
    is_used = Column(Boolean, nullable=False, default=False)
    last_resend_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.datetime.now(datetime.timezone.utc),
        nullable=False,
    )

    user = relationship("User", back_populates="otp_challenges")

    # ------------------------------------------------------------------ helpers
    MAX_ATTEMPTS = 5
    OTP_TTL_MINUTES = 10
    RESEND_COOLDOWN_SECONDS = 60

    def is_expired(self) -> bool:
        now = datetime.datetime.now(datetime.timezone.utc)
        exp = self.expires_at
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=datetime.timezone.utc)
        return now >= exp

    def is_locked(self) -> bool:
        return self.attempts >= self.MAX_ATTEMPTS

    def is_valid(self) -> bool:
        return not self.is_used and not self.is_expired() and not self.is_locked()
