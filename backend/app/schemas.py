import datetime
from typing import Optional, List
from pydantic import BaseModel, EmailStr
from .models import MoveType, MoveStatus, Role


# ---------- Auth ----------
class RegisterIn(BaseModel):
    name: str
    email: EmailStr
    password: str
    role: str = "WAREHOUSE_STAFF"


class SignupIn(RegisterIn):
    pass


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_name: str
    role: str
    user_id: Optional[int] = None
    email: Optional[str] = None
    is_manager: Optional[bool] = None


class UserOut(BaseModel):
    id: int
    name: str
    email: str
    role: str
    is_active: bool
    is_manager: bool
    created_at: Optional[datetime.datetime] = None

    class Config:
        from_attributes = True


class ForgotPasswordIn(BaseModel):
    email: EmailStr


class ResetPasswordIn(BaseModel):
    email: EmailStr
    # Accept both 'otp_code' (existing) and 'otp' (new Flutter field name)
    otp_code: Optional[str] = None
    otp: Optional[str] = None
    new_password: str

    def resolved_otp(self) -> str:
        """Return whichever OTP field the caller provided."""
        return (self.otp_code or self.otp or "").strip()


class VerifyOtpIn(BaseModel):
    email: EmailStr
    otp: Optional[str] = None
    otp_code: Optional[str] = None

    def resolved_otp(self) -> str:
        """Return whichever OTP field the caller provided."""
        return (self.otp or self.otp_code or "").strip()


class VerifyOtpResponse(BaseModel):
    message: str = "OTP verified successfully."
    valid: bool = True


class MessageResponse(BaseModel):
    message: str
    demo_otp: Optional[str] = None


class ForgotPasswordResponse(BaseModel):
    """
    Sent in response to POST /forgot-password.

    In production: message only (no OTP).
    In demo mode (STOCKSENSE_DEMO_MODE=1): demo_otp is '123456', is_demo=True.
    In development (STOCKSENSE_DEV_EXPOSE_OTP=1): demo_otp is populated.
    """
    message: str
    demo_otp: Optional[str] = None
    is_demo: bool = False


# ---------- Category (Section 9) ----------
class CategoryIn(BaseModel):
    name: str
    description: Optional[str] = None
    is_active: bool = True


class CategoryOut(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    is_active: bool = True
    created_at: Optional[datetime.datetime] = None

    class Config:
        from_attributes = True


# ---------- Product (Section 10) ----------
class ProductIn(BaseModel):
    name: str
    sku: str
    category_id: Optional[int] = None
    unit_of_measure: str = "unit"
    unit_cost: Optional[float] = None
    cost_per_unit: Optional[float] = None
    reorder_level: Optional[float] = None
    reorder_point: Optional[float] = None
    is_active: bool = True


class ProductOut(BaseModel):
    id: int
    name: str
    sku: str
    category_id: Optional[int] = None
    unit_of_measure: str = "unit"
    unit_cost: float = 0.0
    cost_per_unit: float = 0.0
    reorder_level: float = 0.0
    reorder_point: float = 0.0
    is_active: bool = True
    created_at: Optional[datetime.datetime] = None
    updated_at: Optional[datetime.datetime] = None

    class Config:
        from_attributes = True


class ProductStockOut(BaseModel):
    product_id: int
    product_name: str
    sku: str
    cost_per_unit: float
    on_hand: float
    reserved: float = 0.0
    free_to_use: float
    reorder_point: float
    low_stock: bool
    warehouse_name: Optional[str] = "Main Warehouse"
    location_name: Optional[str] = "Rack A"
    unit_of_measure: str = "kg"
    status: str = "NORMAL"


# ---------- Warehouse (Section 11) ----------
class WarehouseIn(BaseModel):
    name: str
    short_code: str
    address: Optional[str] = None
    is_active: bool = True


class WarehouseOut(BaseModel):
    id: int
    name: str
    short_code: str
    address: Optional[str] = None
    is_active: bool = True
    created_at: Optional[datetime.datetime] = None
    updated_at: Optional[datetime.datetime] = None

    class Config:
        from_attributes = True


# ---------- Location (Section 12) ----------
class LocationIn(BaseModel):
    name: str
    short_code: str
    warehouse_id: Optional[int] = None
    is_virtual: bool = False
    is_active: bool = True


class LocationOut(BaseModel):
    id: int
    warehouse_id: Optional[int] = None
    name: str
    short_code: str
    is_virtual: bool = False
    is_active: bool = True
    created_at: Optional[datetime.datetime] = None
    updated_at: Optional[datetime.datetime] = None

    class Config:
        from_attributes = True


# ---------- Stock Move (Receipts / Deliveries / Transfers / Adjustments) ----------
class StockMoveIn(BaseModel):
    product_id: int
    from_location_id: Optional[int] = None
    to_location_id: Optional[int] = None
    quantity: float
    contact: Optional[str] = None
    scheduled_date: Optional[datetime.datetime] = None


class StockMoveOut(BaseModel):
    id: int
    reference: str
    move_type: MoveType
    product_id: int
    product_name: str
    from_location_id: Optional[int]
    from_location_name: Optional[str]
    to_location_id: Optional[int]
    to_location_name: Optional[str]
    quantity: float
    status: MoveStatus
    contact: Optional[str]
    scheduled_date: Optional[datetime.datetime]
    created_at: datetime.datetime
    done_at: Optional[datetime.datetime]

    class Config:
        from_attributes = True


class AdjustmentIn(BaseModel):
    product_id: int
    location_id: int
    counted_quantity: float
    contact: Optional[str] = "Stock Count"
    reason: Optional[str] = "Inventory Count Reconciliation"


# ---------- Unified Transaction (Sections 14, 15, 18) ----------
class TransactionItemIn(BaseModel):
    product_id: int
    quantity: float
    adjustment_delta: Optional[float] = None


class TransactionItemOut(BaseModel):
    id: int
    transaction_id: int
    product_id: int
    quantity: float
    adjustment_delta: Optional[float] = None
    product_name: Optional[str] = None
    sku: Optional[str] = None

    class Config:
        from_attributes = True


class TransactionIn(BaseModel):
    type: str  # RECEIPT, DELIVERY, TRANSFER, ADJUSTMENT
    source_location_id: Optional[int] = None
    destination_location_id: Optional[int] = None
    party_name: Optional[str] = None
    contact: Optional[str] = None
    delivery_address: Optional[str] = None
    schedule_date: Optional[datetime.datetime] = None
    reason: Optional[str] = None
    warehouse_code: Optional[str] = "WH"
    items: List[TransactionItemIn] = []


class TransactionOut(BaseModel):
    id: int
    reference: str
    type: str
    status: str
    source_location_id: Optional[int] = None
    destination_location_id: Optional[int] = None
    party_name: Optional[str] = None
    contact: Optional[str] = None
    delivery_address: Optional[str] = None
    schedule_date: Optional[datetime.datetime] = None
    reason: Optional[str] = None
    created_by: Optional[int] = None
    validated_by: Optional[int] = None
    created_at: Optional[datetime.datetime] = None
    updated_at: Optional[datetime.datetime] = None
    validated_at: Optional[datetime.datetime] = None
    canceled_at: Optional[datetime.datetime] = None
    items: List[TransactionItemOut] = []

    class Config:
        from_attributes = True


# ---------- Dashboard (Section 26 & 27) ----------
class LowStockProductItem(BaseModel):
    product_id: int
    product_name: str
    sku: str
    category_name: Optional[str] = None
    unit_of_measure: str = "unit"
    cost_per_unit: float = 0.0
    on_hand: float
    reserved: float
    free_to_use: float
    reorder_level: float
    status: str  # "OUT OF STOCK", "LOW STOCK", "NORMAL"

    class Config:
        from_attributes = True


class RecentMovementItem(BaseModel):
    id: int
    reference: str
    type: str  # RECEIPT, DELIVERY, TRANSFER, ADJUSTMENT
    status: str
    product_name: str
    sku: str
    quantity: float
    from_location: Optional[str] = None
    to_location: Optional[str] = None
    created_at: Optional[datetime.datetime] = None

    class Config:
        from_attributes = True


class IntelligencePreview(BaseModel):
    total_stock_value: float = 0.0
    fast_moving_items: List[str] = []
    dead_stock_count: int = 0
    reorder_recommended_count: int = 0
    top_moving_product: Optional[str] = None


class DashboardSummaryOut(BaseModel):
    # Core display fields (Section 26)
    total_stock: float
    low_stock: int
    out_of_stock: int
    pending_receipts: int
    pending_deliveries: int
    waiting_deliveries: int
    transfers_scheduled: int

    # Backward compatibility fields
    total_products: int
    low_stock_count: int
    out_of_stock_count: int

    # Also show (Section 26)
    low_stock_products: List[LowStockProductItem] = []
    recent_movements: List[RecentMovementItem] = []
    intelligence_preview: IntelligencePreview


class DashboardOut(DashboardSummaryOut):
    pass


# ---------- Section 28: Inventory Intelligence ----------
class StockoutItem(BaseModel):
    product_id: int
    product_name: str
    sku: str
    current_stock: float
    average_daily_usage: Optional[float] = None
    reorder_level: float
    estimated_days_to_reorder: Optional[float] = None
    estimated_days_to_stockout: Optional[float] = None
    has_sufficient_history: bool = True
    message: Optional[str] = None


class ReorderItem(BaseModel):
    product_id: int
    product_name: str
    sku: str
    current_stock: float
    average_usage: Optional[float] = None
    target_coverage: int = 30  # Days
    recommended_reorder_quantity: float
    explanation: str
    has_sufficient_history: bool = True
    message: Optional[str] = None


# ---------- Section 24: Stock Ledger ----------
class StockLedgerOut(BaseModel):
    id: int
    transaction_id: Optional[int] = None
    product_id: int
    product_name: Optional[str] = None
    sku: Optional[str] = None
    location_id: int
    location_name: Optional[str] = None
    warehouse_name: Optional[str] = None
    quantity_before: float
    quantity_change: float
    quantity_after: float
    movement_type: str  # RECEIPT, DELIVERY, TRANSFER_IN, TRANSFER_OUT, ADJUSTMENT
    reference: Optional[str] = None
    created_at: datetime.datetime

    class Config:
        from_attributes = True


# ---------- Section 25: Move History (Derived) ----------
class DerivedMoveOut(BaseModel):
    id: int
    reference: str
    date: datetime.datetime
    contact: Optional[str] = None
    from_location: Optional[str] = None
    from_location_id: Optional[int] = None
    to_location: Optional[str] = None
    to_location_id: Optional[int] = None
    product_id: int
    product_name: str
    sku: str
    quantity: float
    status: str
    type: str
    ledger_entries: List[StockLedgerOut] = []

    class Config:
        from_attributes = True


