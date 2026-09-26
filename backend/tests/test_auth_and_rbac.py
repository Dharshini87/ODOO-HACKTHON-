import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.db.base import Base
from app.database import get_db
from app import models
from app.core import security, dependencies


from sqlalchemy.pool import StaticPool

@pytest.fixture(scope="function")
def client_and_db():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db

    client = TestClient(app)
    db = TestingSessionLocal()

    yield client, db

    db.close()
    Base.metadata.drop_all(bind=engine)
    app.dependency_overrides.clear()


def test_user_registration_and_password_hashing(client_and_db):
    """Section 5 & 8: Register endpoint and password hashing."""
    client, db = client_and_db

    payload = {
        "name": "Jane Staff",
        "email": "jane@stocksense.com",
        "password": "Password123!",
        "role": "WAREHOUSE_STAFF",
    }
    response = client.post("/api/auth/register", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert "access_token" in data
    assert data["user_name"] == "Jane Staff"
    assert data["role"] == "WAREHOUSE_STAFF"
    assert data["is_manager"] is False

    # Verify user in database
    user = db.query(models.User).filter_by(email="jane@stocksense.com").first()
    assert user is not None
    assert user.password_hash != "Password123!"
    assert security.verify_password("Password123!", user.password_hash)

    # Duplicate registration must fail
    dup_res = client.post("/api/auth/register", json=payload)
    assert dup_res.status_code == 400


def test_user_login_json_and_form(client_and_db):
    """Section 5: Login via JSON and OAuth2 Form."""
    client, db = client_and_db

    # Register user first
    reg_payload = {
        "name": "John Manager",
        "email": "john@stocksense.com",
        "password": "ManagerPass123!",
        "role": "INVENTORY_MANAGER",
    }
    client.post("/api/auth/register", json=reg_payload)

    # 1. Login with JSON payload
    login_json_res = client.post(
        "/api/auth/login",
        json={"email": "john@stocksense.com", "password": "ManagerPass123!"},
    )
    assert login_json_res.status_code == 200
    token_data = login_json_res.json()
    assert "access_token" in token_data
    assert token_data["is_manager"] is True

    # 2. Login with OAuth2 form data
    login_form_res = client.post(
        "/api/auth/login",
        data={"username": "john@stocksense.com", "password": "ManagerPass123!"},
    )
    assert login_form_res.status_code == 200
    assert "access_token" in login_form_res.json()

    # 3. Bad password must fail
    bad_login_res = client.post(
        "/api/auth/login",
        json={"email": "john@stocksense.com", "password": "WrongPassword!"},
    )
    assert bad_login_res.status_code == 401


def test_deactivated_user_cannot_login(client_and_db):
    """Section 8 & 43: Deactivated (soft-deleted) user cannot authenticate."""
    client, db = client_and_db

    # Create inactive user
    user = models.User(
        name="Deactivated Staff",
        email="inactive@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="WAREHOUSE_STAFF",
        is_active=False,
    )
    db.add(user)
    db.commit()

    res = client.post(
        "/api/auth/login",
        json={"email": "inactive@stocksense.com", "password": "Pass123!"},
    )
    assert res.status_code in (401, 403)


def test_forgot_password_and_otp_reset(client_and_db):
    """Section 5: Forgot password OTP flow and password reset."""
    client, db = client_and_db

    reg_payload = {
        "name": "Alex User",
        "email": "alex@stocksense.com",
        "password": "OldPassword123!",
        "role": "WAREHOUSE_STAFF",
    }
    client.post("/api/auth/register", json=reg_payload)

    # Request password reset OTP
    fp_res = client.post(
        "/api/auth/forgot-password",
        json={"email": "alex@stocksense.com"},
    )
    assert fp_res.status_code == 200
    fp_data = fp_res.json()
    otp_code = fp_data.get("demo_otp")
    assert otp_code is not None
    assert len(otp_code) == 6

    # Verify token stored in password_reset_tokens table
    reset_record = db.query(models.PasswordResetToken).filter_by(otp_code=otp_code).first()
    assert reset_record is not None
    assert reset_record.is_used is False

    # Attempt reset with wrong OTP fails
    bad_reset = client.post(
        "/api/auth/reset-password",
        json={
            "email": "alex@stocksense.com",
            "otp_code": "000000",
            "new_password": "NewBrandPassword123!",
        },
    )
    assert bad_reset.status_code == 400

    # Reset with valid OTP succeeds
    good_reset = client.post(
        "/api/auth/reset-password",
        json={
            "email": "alex@stocksense.com",
            "otp_code": otp_code,
            "new_password": "NewBrandPassword123!",
        },
    )
    assert good_reset.status_code == 200

    # Verify single-use: cannot reuse the same OTP
    reuse_reset = client.post(
        "/api/auth/reset-password",
        json={
            "email": "alex@stocksense.com",
            "otp_code": otp_code,
            "new_password": "AnotherPassword123!",
        },
    )
    assert reuse_reset.status_code == 400

    # Verify login with new password succeeds
    login_new = client.post(
        "/api/auth/login",
        json={"email": "alex@stocksense.com", "password": "NewBrandPassword123!"},
    )
    assert login_new.status_code == 200


def test_rbac_permissions_matrix(client_and_db):
    """Section 6: Enforce RBAC permissions matrix in FastAPI."""
    client, db = client_and_db

    staff_user = models.User(
        name="Staff Member",
        email="staff@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="WAREHOUSE_STAFF",
        is_active=True,
    )
    manager_user = models.User(
        name="Manager Member",
        email="manager@stocksense.com",
        password_hash=security.hash_password("Pass123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    db.add_all([staff_user, manager_user])
    db.commit()

    # Manager has all permissions
    assert manager_user.has_permission("validate_adjustment") is True
    assert manager_user.has_permission("manage_products") is True
    assert manager_user.has_permission("manage_categories") is True
    assert manager_user.has_permission("manage_warehouses") is True
    assert manager_user.has_permission("manage_locations") is True
    assert manager_user.has_permission("cancel_other_transaction") is True

    # Staff permissions check
    assert staff_user.has_permission("create_receipt") is True
    assert staff_user.has_permission("validate_receipt") is True
    assert staff_user.has_permission("create_delivery") is True
    assert staff_user.has_permission("validate_delivery") is True
    assert staff_user.has_permission("create_transfer") is True
    assert staff_user.has_permission("validate_transfer") is True
    assert staff_user.has_permission("create_adjustment") is True
    assert staff_user.has_permission("view_dashboard") is True
    assert staff_user.has_permission("view_stock") is True
    assert staff_user.has_permission("view_ledger") is True
    assert staff_user.has_permission("view_move_history") is True

    # Staff RESTRICTED permissions (must be False)
    assert staff_user.has_permission("validate_adjustment") is False
    assert staff_user.has_permission("manage_products") is False
    assert staff_user.has_permission("manage_categories") is False
    assert staff_user.has_permission("manage_warehouses") is False
    assert staff_user.has_permission("manage_locations") is False
    assert staff_user.has_permission("cancel_other_transaction") is False


def test_transaction_cancellation_rbac(client_and_db):
    """
    Section 6 Rule:
    Cancel own transaction: STAFF = YES, MANAGER = YES
    Cancel another user's transaction: STAFF = NO, MANAGER = YES
    """
    client, db = client_and_db

    staff1 = models.User(
        name="Staff 1",
        email="s1@test.com",
        password_hash="h",
        role="WAREHOUSE_STAFF",
    )
    staff2 = models.User(
        name="Staff 2",
        email="s2@test.com",
        password_hash="h",
        role="WAREHOUSE_STAFF",
    )
    manager = models.User(
        name="Manager",
        email="mgr@test.com",
        password_hash="h",
        role="INVENTORY_MANAGER",
    )
    db.add_all([staff1, staff2, manager])
    db.commit()

    # 1. Staff 1 canceling Staff 1's own transaction: ALLOWED
    dependencies.check_transaction_cancellation_permission(
        created_by_user_id=staff1.id,
        current_user=staff1,
    )

    # 2. Staff 1 canceling Staff 2's transaction: BLOCKED (403 Forbidden)
    with pytest.raises(Exception) as excinfo:
        dependencies.check_transaction_cancellation_permission(
            created_by_user_id=staff2.id,
            current_user=staff1,
        )
    assert "Staff members can only cancel their own transactions" in str(excinfo.value)

    # 3. Manager canceling Staff 1's transaction: ALLOWED
    dependencies.check_transaction_cancellation_permission(
        created_by_user_id=staff1.id,
        current_user=manager,
    )
