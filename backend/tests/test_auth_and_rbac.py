import pytest
from decimal import Decimal
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


# ============================================================
# RBAC PHASE 3: AUTHORIZATION TESTS (8 SPECIFIED REQUIREMENTS)
# ============================================================

@pytest.fixture
def rbac_fixture(client_and_db):
    client, db = client_and_db

    manager = models.User(
        name="Elena Manager",
        email="manager@stocksense.com",
        password_hash=security.hash_password("Manager123!"),
        role="INVENTORY_MANAGER",
        is_active=True,
    )
    staff1 = models.User(
        name="Sam Staff",
        email="staff1@stocksense.com",
        password_hash=security.hash_password("Staff123!"),
        role="WAREHOUSE_STAFF",
        is_active=True,
    )
    staff2 = models.User(
        name="Other Staff",
        email="staff2@stocksense.com",
        password_hash=security.hash_password("Staff123!"),
        role="WAREHOUSE_STAFF",
        is_active=True,
    )
    db.add_all([manager, staff1, staff2])
    db.commit()

    # Master data: Warehouse, Locations, Product, Category
    cat = models.Category(name="Electronics", is_active=True)
    wh = models.Warehouse(name="Central Depot", short_code="CD1", address="123 Industrial Way", is_active=True)
    db.add_all([cat, wh])
    db.commit()

    loc1 = models.Location(warehouse_id=wh.id, name="Rack 01", short_code="RACK-01", is_active=True)
    loc2 = models.Location(warehouse_id=wh.id, name="Rack 02", short_code="RACK-02", is_active=True)
    prod = models.Product(
        name="Sensor Unit",
        sku="SNS-100",
        category_id=cat.id,
        unit_of_measure="pcs",
        cost_per_unit=Decimal("45.00"),
        reorder_point=Decimal("10.000"),
        is_active=True,
    )
    db.add_all([loc1, loc2, prod])
    db.commit()

    mgr_token = security.create_access_token({"sub": manager.email, "role": manager.role, "user_id": manager.id})
    staff1_token = security.create_access_token({"sub": staff1.email, "role": staff1.role, "user_id": staff1.id})
    staff2_token = security.create_access_token({"sub": staff2.email, "role": staff2.role, "user_id": staff2.id})

    class RBACTestContext:
        def __init__(self):
            self.client = client
            self.db = db
            self.manager = manager
            self.staff1 = staff1
            self.staff2 = staff2
            self.mgr_headers = {"Authorization": f"Bearer {mgr_token}"}
            self.staff1_headers = {"Authorization": f"Bearer {staff1_token}"}
            self.staff2_headers = {"Authorization": f"Bearer {staff2_token}"}
            self.warehouse = wh
            self.loc1 = loc1
            self.loc2 = loc2
            self.product = prod
            self.category = cat

    return RBACTestContext()


def test_rbac_1_staff_allowed_endpoint(rbac_fixture):
    """
    Requirement 1: Staff allowed endpoint.
    Warehouse staff can access baseline allowed endpoints:
    - view dashboard, view stock, view products, view categories, view warehouses, view locations, view profile
    """
    c = rbac_fixture.client
    h = rbac_fixture.staff1_headers

    endpoints = [
        "/api/dashboard/summary",
        "/api/stock",
        "/api/products",
        "/api/categories",
        "/api/warehouses",
        "/api/warehouses/locations",
        "/api/move-history",
        "/api/auth/me",
        "/api/notifications",
    ]
    for ep in endpoints:
        res = c.get(ep, headers=h)
        assert res.status_code == 200, f"Staff should be allowed on {ep}, got {res.status_code}: {res.text}"

    # Verify profile reflects database role
    me_res = c.get("/api/auth/me", headers=h)
    assert me_res.status_code == 200
    me_data = me_res.json()
    assert me_data["role"] == "WAREHOUSE_STAFF"
    assert me_data["is_manager"] is False


def test_rbac_2_manager_allowed_endpoint(rbac_fixture):
    """
    Requirement 2: Manager allowed endpoint.
    Inventory Manager has full access to create/manage products, categories, warehouses, locations, and settings.
    """
    c = rbac_fixture.client
    h = rbac_fixture.mgr_headers

    # Manager can access system settings
    settings_res = c.get("/api/system/settings", headers=h)
    assert settings_res.status_code == 200
    assert settings_res.json()["status"] == "success"

    # Manager can create category
    cat_res = c.post("/api/categories", json={"name": "Tools"}, headers=h)
    assert cat_res.status_code == 201

    # Manager can create product
    prod_res = c.post(
        "/api/products",
        json={
            "name": "Drill Bit",
            "sku": "DRL-001",
            "category_id": cat_res.json()["id"],
            "cost_per_unit": 12.50,
            "reorder_point": 5,
        },
        headers=h,
    )
    assert prod_res.status_code == 201

    # Manager can create warehouse
    wh_res = c.post(
        "/api/warehouses",
        json={"name": "North Annex", "short_code": "NA1"},
        headers=h,
    )
    assert wh_res.status_code == 201

    # Manager can create location
    loc_res = c.post(
        "/api/warehouses/locations",
        json={"name": "Bin 99", "short_code": "BIN-99", "warehouse_id": wh_res.json()["id"]},
        headers=h,
    )
    assert loc_res.status_code == 201


def test_rbac_3_staff_denied_manager_endpoint_returns_403(rbac_fixture):
    """
    Requirement 3: Staff denied manager endpoint -> 403.
    Warehouse staff must receive HTTP 403 Forbidden when calling manager-only endpoints.
    """
    c = rbac_fixture.client
    h = rbac_fixture.staff1_headers

    # Attempting manager-only product creation
    res1 = c.post(
        "/api/products",
        json={"name": "Unauthorized Prod", "sku": "UNAUTH-1"},
        headers=h,
    )
    assert res1.status_code == 403, f"Expected 403, got {res1.status_code}"
    assert "INVENTORY_MANAGER" in res1.json()["detail"] or "Forbidden" in res1.json()["detail"] or "Permission denied" in res1.json()["detail"]

    # Attempting manager-only category creation
    res2 = c.post(
        "/api/categories",
        json={"name": "Unauthorized Cat"},
        headers=h,
    )
    assert res2.status_code == 403

    # Attempting manager-only warehouse creation
    res3 = c.post(
        "/api/warehouses",
        json={"name": "Unauthorized WH", "short_code": "UWH"},
        headers=h,
    )
    assert res3.status_code == 403

    # Attempting manager-only system settings access
    res4 = c.get("/api/system/settings", headers=h)
    assert res4.status_code == 403


def test_rbac_4_manager_only_adjustment_validation_staff_gets_403(rbac_fixture):
    """
    Requirement 4: Manager-only adjustment validation -> Staff gets 403.
    Staff can CREATE adjustments, but ONLY Inventory Manager can VALIDATE adjustments.
    """
    c = rbac_fixture.client
    staff_h = rbac_fixture.staff1_headers
    mgr_h = rbac_fixture.mgr_headers

    # 1. Staff creates adjustment (Staff ALLOWED to create adjustments)
    adj_res = c.post(
        "/api/adjustments",
        json={
            "location_id": rbac_fixture.loc1.id,
            "product_id": rbac_fixture.product.id,
            "physical_count": 25.0,
            "reason": "Damaged",
        },
        headers=staff_h,
    )
    assert adj_res.status_code in (200, 201), f"Staff should be able to create adjustment: {adj_res.text}"
    adj_id = adj_res.json()["id"]

    # 2. Staff attempts to validate adjustment -> MUST GET 403 FORBIDDEN
    val_res_staff = c.post(f"/api/adjustments/{adj_id}/validate", headers=staff_h)
    assert val_res_staff.status_code == 403, f"Staff must receive 403 when validating adjustment: {val_res_staff.text}"
    assert "INVENTORY_MANAGER" in val_res_staff.json()["detail"]

    # 3. Manager validates adjustment -> SUCCEEDS (200 OK)
    val_res_mgr = c.post(f"/api/adjustments/{adj_id}/validate", headers=mgr_h)
    assert val_res_mgr.status_code == 200, f"Manager must succeed on adjustment validation: {val_res_mgr.text}"
    assert val_res_mgr.json()["status"] == "done"


def test_rbac_5_staff_cannot_manage_products(rbac_fixture):
    """
    Requirement 5: Staff cannot manage products.
    Staff cannot create, edit, or delete products (all return 403).
    """
    c = rbac_fixture.client
    staff_h = rbac_fixture.staff1_headers
    mgr_h = rbac_fixture.mgr_headers
    prod_id = rbac_fixture.product.id

    # Create fails for staff
    res_create = c.post("/api/products", json={"name": "P2", "sku": "P2-SKU"}, headers=staff_h)
    assert res_create.status_code == 403

    # Update fails for staff
    res_update = c.put(f"/api/products/{prod_id}", json={"name": "P New Name", "sku": "SNS-100"}, headers=staff_h)
    assert res_update.status_code == 403

    # Delete fails for staff
    res_delete = c.delete(f"/api/products/{prod_id}", headers=staff_h)
    assert res_delete.status_code == 403

    # Category management also fails for staff
    res_cat_create = c.post("/api/categories", json={"name": "Hardware"}, headers=staff_h)
    assert res_cat_create.status_code == 403
    res_cat_del = c.delete(f"/api/categories/{rbac_fixture.category.id}", headers=staff_h)
    assert res_cat_del.status_code == 403

    # Manager CAN update product
    res_mgr_up = c.put(f"/api/products/{prod_id}", json={"name": "SNS Updated", "sku": "SNS-100"}, headers=mgr_h)
    assert res_mgr_up.status_code == 200


def test_rbac_6_staff_cannot_manage_warehouses_and_locations(rbac_fixture):
    """
    Requirement 6: Staff cannot manage warehouses/locations.
    Staff cannot create, edit, or delete warehouses or locations (all return 403).
    """
    c = rbac_fixture.client
    staff_h = rbac_fixture.staff1_headers
    mgr_h = rbac_fixture.mgr_headers
    wh_id = rbac_fixture.warehouse.id
    loc_id = rbac_fixture.loc1.id

    # Warehouse operations fail for staff
    res_wh_create = c.post("/api/warehouses", json={"name": "W2", "short_code": "W2"}, headers=staff_h)
    assert res_wh_create.status_code == 403

    res_wh_update = c.put(f"/api/warehouses/{wh_id}", json={"name": "W New Name", "short_code": "CD1"}, headers=staff_h)
    assert res_wh_update.status_code == 403

    res_wh_delete = c.delete(f"/api/warehouses/{wh_id}", headers=staff_h)
    assert res_wh_delete.status_code == 403

    # Location operations fail for staff
    res_loc_create = c.post("/api/warehouses/locations", json={"name": "L3", "short_code": "L3", "warehouse_id": wh_id}, headers=staff_h)
    assert res_loc_create.status_code == 403

    res_loc_update = c.put(f"/api/warehouses/locations/{loc_id}", json={"name": "L New Name", "short_code": "RACK-01", "warehouse_id": wh_id}, headers=staff_h)
    assert res_loc_update.status_code == 403

    res_loc_delete = c.delete(f"/api/warehouses/locations/{loc_id}", headers=staff_h)
    assert res_loc_delete.status_code == 403

    # Manager CAN update warehouse
    res_mgr_wh = c.put(f"/api/warehouses/{wh_id}", json={"name": "Central Hub Renamed", "short_code": "CD1"}, headers=mgr_h)
    assert res_mgr_wh.status_code == 200


def test_rbac_7_staff_cannot_access_system_settings(rbac_fixture):
    """
    Requirement 7: Staff cannot access system settings.
    Manager-only system settings endpoint returns 403 for staff, 200 for manager.
    """
    c = rbac_fixture.client
    staff_h = rbac_fixture.staff1_headers
    mgr_h = rbac_fixture.mgr_headers

    system_settings_paths = [
        "/api/system/settings",
        "/system/settings",
        "/api/settings/system",
        "/settings/system",
        "/api/auth/system/settings",
        "/auth/system/settings",
    ]
    for path in system_settings_paths:
        staff_res = c.get(path, headers=staff_h)
        assert staff_res.status_code == 403, f"Staff must receive 403 on {path}, got {staff_res.status_code}"
        assert "INVENTORY_MANAGER" in staff_res.json()["detail"]

        mgr_res = c.get(path, headers=mgr_h)
        assert mgr_res.status_code == 200, f"Manager must receive 200 on {path}, got {mgr_res.status_code}"
        assert mgr_res.json()["status"] == "success"


def test_rbac_8_existing_permitted_operations_still_work(rbac_fixture):
    """
    Requirement 8: Existing permitted operations still work.
    Full verification that warehouse staff can execute their end-to-end permitted operations:
    - Create receipt & validate receipt
    - Create transfer & validate transfer
    - Create delivery & validate delivery
    - Create adjustment
    - View move history, stock ledger, dashboard, and notifications
    - Cancel own transaction, but 403 when trying to cancel another user's transaction
    """
    c = rbac_fixture.client
    staff1_h = rbac_fixture.staff1_headers
    staff2_h = rbac_fixture.staff2_headers
    mgr_h = rbac_fixture.mgr_headers
    prod_id = rbac_fixture.product.id
    loc1_id = rbac_fixture.loc1.id
    loc2_id = rbac_fixture.loc2.id

    # 1. Staff creates and validates a Receipt (100 units at loc1)
    rcpt_res = c.post(
        "/api/receipts",
        json={"to_location_id": loc1_id, "product_id": prod_id, "quantity": 100.0, "contact": "Supplier Co"},
        headers=staff1_h,
    )
    assert rcpt_res.status_code in (200, 201)
    rcpt_id = rcpt_res.json()["id"]

    val_rcpt = c.post(f"/api/receipts/{rcpt_id}/validate", headers=staff1_h)
    assert val_rcpt.status_code == 200
    assert val_rcpt.json()["status"] == "done"

    # 2. Staff creates and validates a Transfer (Loc 1 -> Loc 2, 30 units)
    trf_res = c.post(
        "/api/transfers",
        json={"from_location_id": loc1_id, "to_location_id": loc2_id, "product_id": prod_id, "quantity": 30.0},
        headers=staff1_h,
    )
    assert trf_res.status_code in (200, 201)
    trf_id = trf_res.json()["id"]

    c.post(f"/api/transfers/{trf_id}/ready", headers=staff1_h)
    val_trf = c.post(f"/api/transfers/{trf_id}/validate", headers=staff1_h)
    assert val_trf.status_code == 200
    assert val_trf.json()["status"] == "done"

    # 3. Staff creates and validates a Delivery (from Loc 1, 20 units)
    deliv_res = c.post(
        "/api/deliveries",
        json={"from_location_id": loc1_id, "product_id": prod_id, "quantity": 20.0, "contact": "ACME Corp"},
        headers=staff1_h,
    )
    assert deliv_res.status_code in (200, 201)
    deliv_id = deliv_res.json()["id"]

    c.post(f"/api/deliveries/{deliv_id}/ready", headers=staff1_h)
    val_deliv = c.post(f"/api/deliveries/{deliv_id}/validate", headers=staff1_h)
    assert val_deliv.status_code == 200
    assert val_deliv.json()["status"] == "done"

    # 4. Staff creates an Adjustment (Draft)
    adj_res = c.post(
        "/api/adjustments",
        json={"location_id": loc2_id, "product_id": prod_id, "physical_count": 28.0, "reason": "Damaged"},
        headers=staff1_h,
    )
    assert adj_res.status_code in (200, 201)

    # 5. Staff views stock, ledger, move history, dashboard, notifications
    assert c.get("/api/stock", headers=staff1_h).status_code == 200
    assert c.get("/api/stock/ledger", headers=staff1_h).status_code == 200
    assert c.get("/api/move-history", headers=staff1_h).status_code == 200
    assert c.get("/api/dashboard/summary", headers=staff1_h).status_code == 200
    assert c.get("/api/notifications", headers=staff1_h).status_code == 200

    # 6. Cancellation RBAC: Staff can cancel OWN transaction, but CANNOT cancel another user's transaction
    # Staff 1 creates a draft receipt and cancels own receipt -> SUCCESS
    own_rcpt = c.post(
        "/api/receipts",
        json={"to_location_id": loc1_id, "product_id": prod_id, "quantity": 5.0, "contact": "Vendor"},
        headers=staff1_h,
    ).json()
    cancel_own = c.post(f"/api/receipts/{own_rcpt['id']}/cancel", headers=staff1_h)
    assert cancel_own.status_code == 200
    assert cancel_own.json()["status"] == "canceled"

    # Staff 2 creates a draft receipt
    staff2_rcpt = c.post(
        "/api/receipts",
        json={"to_location_id": loc1_id, "product_id": prod_id, "quantity": 10.0, "contact": "Vendor"},
        headers=staff2_h,
    ).json()

    # Staff 1 attempts to cancel Staff 2's receipt -> 403 Forbidden!
    cancel_other_by_staff = c.post(f"/api/receipts/{staff2_rcpt['id']}/cancel", headers=staff1_h)
    assert cancel_other_by_staff.status_code == 403
    assert "Staff members can only cancel their own transactions" in cancel_other_by_staff.json()["detail"]

    # Manager CAN cancel Staff 2's receipt -> 200 OK!
    cancel_other_by_mgr = c.post(f"/api/receipts/{staff2_rcpt['id']}/cancel", headers=mgr_h)
    assert cancel_other_by_mgr.status_code == 200
    assert cancel_other_by_mgr.json()["status"] == "canceled"


def test_rbac_security_invariant_database_role_authoritative(rbac_fixture):
    """
    Security Invariant:
    The authenticated user's role MUST come from the backend/database.
    The Flutter client must never be able to assign its own role.
    If an attacker crafts a JWT with role='INVENTORY_MANAGER' for a staff email,
    the backend checks the database role (WAREHOUSE_STAFF) and denies manager access with 403.
    """
    c = rbac_fixture.client

    # Forged JWT with role claim set to INVENTORY_MANAGER, but sub is staff1's email
    forged_token = security.create_access_token({
        "sub": rbac_fixture.staff1.email,
        "role": "INVENTORY_MANAGER",
        "user_id": rbac_fixture.staff1.id,
    })
    forged_headers = {"Authorization": f"Bearer {forged_token}"}

    # Attempting to access manager-only endpoint with forged role claim
    res = c.get("/api/system/settings", headers=forged_headers)
    assert res.status_code == 403, "Database role must override any JWT role claims"

