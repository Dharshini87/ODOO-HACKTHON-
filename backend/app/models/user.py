import enum
import datetime
from sqlalchemy import Column, Integer, String, DateTime, Enum, Boolean
from sqlalchemy.orm import relationship
from ..db.base import Base


class Role(str, enum.Enum):
    WAREHOUSE_STAFF = "WAREHOUSE_STAFF"
    INVENTORY_MANAGER = "INVENTORY_MANAGER"
    # Backwards compatibility values
    staff = "staff"
    manager = "manager"

    @classmethod
    def normalize(cls, value: str) -> "Role":
        if not value:
            return cls.WAREHOUSE_STAFF
        val = str(value).strip().upper()
        if "MANAGE" in val:
            return cls.INVENTORY_MANAGER
        return cls.WAREHOUSE_STAFF


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    email = Column(String(255), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(String(50), default="WAREHOUSE_STAFF", nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)

    otp_code = Column(String(10), nullable=True)
    otp_expiry = Column(DateTime(timezone=True), nullable=True)

    created_at = Column(DateTime(timezone=True), default=datetime.datetime.utcnow, nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        default=datetime.datetime.utcnow,
        onupdate=datetime.datetime.utcnow,
        nullable=False,
    )

    reset_tokens = relationship("PasswordResetToken", back_populates="user", cascade="all, delete-orphan")

    @property
    def is_manager(self) -> bool:
        r = str(self.role).upper()
        return "MANAGER" in r

    @property
    def is_staff(self) -> bool:
        return not self.is_manager

    def has_permission(self, permission: str) -> bool:
        """
        Enforce Section 6 Permission Matrix in FastAPI.
        Frontend visibility is NOT a security mechanism.
        """
        if self.is_manager:
            return True

        # Permissions restricted ONLY to INVENTORY_MANAGER:
        manager_only = {
            "validate_adjustment",
            "manage_products",
            "manage_categories",
            "manage_warehouses",
            "manage_locations",
            "cancel_other_transaction",
            "access_system_settings",
            "manage_system_settings",
        }
        return permission.lower().strip() not in manager_only
