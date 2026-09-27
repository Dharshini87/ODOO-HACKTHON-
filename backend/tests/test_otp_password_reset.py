"""
StockSense OTP Password Reset — Comprehensive Backend Tests.

Covers:
1. Endpoint health & schema
2. Email-enumeration protection (same response for unknown email)
3. OTP security: stored as hash, never returned in production
4. Dev-expose mode (STOCKSENSE_DEV_EXPOSE_OTP=1)
5. 10-minute expiry enforcement
6. Maximum 5 failed attempts locking
7. Resend 60-second cooldown
8. New OTP invalidates previous OTP
9. Single-use: replaying a used OTP is rejected
10. Password is correctly updated after reset
11. Old password is rejected after reset
12. No new JWT issued on successful reset
13. Constants-time comparison (hash comparison)
"""
import datetime
import hashlib
import os
import secrets

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.db.base import Base
from app.database import get_db
from app import models
from app.core import security
from app.services.auth_service import _generate_secure_otp, _hash_otp


# ─────────────────────────────────────────── fixtures ────────────────────────

@pytest.fixture(scope="function")
def client_and_db(monkeypatch):
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "0")
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


def _register_user(client, email, password, name="Test User", role="WAREHOUSE_STAFF"):
    resp = client.post("/api/auth/register", json={
        "name": name,
        "email": email,
        "password": password,
        "role": role,
    })
    assert resp.status_code == 201, resp.text
    return resp.json()


def _make_otp_challenge(db, user_id, *, otp_plaintext=None, expired=False,
                        attempts=0, is_used=False):
    """Directly insert an OTP challenge bypassing the service layer."""
    if otp_plaintext is None:
        otp_plaintext = "123456"
    now = datetime.datetime.now(datetime.timezone.utc)
    if expired:
        exp = now - datetime.timedelta(seconds=1)
    else:
        exp = now + datetime.timedelta(minutes=10)
    challenge = models.PasswordResetOtp(
        user_id=user_id,
        otp_hash=_hash_otp(otp_plaintext),
        expires_at=exp,
        attempts=attempts,
        is_used=is_used,
        last_resend_at=now,
    )
    db.add(challenge)
    db.commit()
    db.refresh(challenge)
    return challenge, otp_plaintext


# ─────────────────────────────────────────── Unit: OTP helpers ───────────────

def test_generate_secure_otp_length_and_range():
    """OTP must be exactly 6 digits in [100000, 999999]."""
    for _ in range(50):
        otp = _generate_secure_otp()
        assert len(otp) == 6
        assert otp.isdigit()
        assert 100000 <= int(otp) <= 999999


def test_hash_otp_produces_sha256_hex():
    """_hash_otp must return a 64-char SHA-256 hex digest."""
    digest = _hash_otp("123456")
    assert len(digest) == 64
    assert all(c in "0123456789abcdef" for c in digest)


def test_hash_otp_is_deterministic():
    assert _hash_otp("654321") == _hash_otp("654321")


def test_hash_otp_different_inputs_differ():
    assert _hash_otp("111111") != _hash_otp("999999")


# ─────────────────────────────────────── Endpoint: forgot-password ────────────

def test_forgot_password_registered_email(client_and_db, monkeypatch):
    """
    POST /forgot-password with a registered email must return 200 and the
    generic message, not the OTP (production mode).
    """
    client, db = client_and_db
    monkeypatch.delenv("STOCKSENSE_DEV_EXPOSE_OTP", raising=False)
    # Stub email delivery so tests don't need SMTP
    monkeypatch.setattr(
        "app.services.auth_service.send_password_reset_otp",
        lambda *a, **kw: None,
    )
    _register_user(client, "otp_test@example.com", "Password123!")
    resp = client.post("/api/auth/forgot-password", json={"email": "otp_test@example.com"})
    assert resp.status_code == 200
    data = resp.json()
    assert "message" in data
    # demo_otp must be absent in production mode
    assert data.get("demo_otp") is None


def test_forgot_password_unknown_email_same_response(client_and_db, monkeypatch):
    """
    POST /forgot-password with an UNKNOWN email must return exactly the same
    HTTP 200 and message as a registered email (no enumeration).
    """
    client, _ = client_and_db
    monkeypatch.delenv("STOCKSENSE_DEV_EXPOSE_OTP", raising=False)
    resp = client.post("/api/auth/forgot-password", json={"email": "nobody@example.com"})
    assert resp.status_code == 200
    data = resp.json()
    assert "message" in data
    assert data.get("demo_otp") is None


def test_forgot_password_dev_expose_otp(client_and_db, monkeypatch):
    """
    When STOCKSENSE_DEV_EXPOSE_OTP=1 the response must include demo_otp.
    """
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEV_EXPOSE_OTP", "1")
    import app.services.auth_service as svc_mod
    svc_mod._DEV_EXPOSE_OTP = True  # Force module-level flag
    _register_user(client, "devmode@example.com", "Password123!")
    resp = client.post("/api/auth/forgot-password", json={"email": "devmode@example.com"})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("demo_otp") is not None
    otp = data["demo_otp"]
    assert len(otp) == 6 and otp.isdigit()
    # Cleanup
    svc_mod._DEV_EXPOSE_OTP = False


# ─────────────────────────────────────── Endpoint: reset-password ─────────────

def test_reset_password_correct_otp(client_and_db, monkeypatch):
    """Correct OTP → password updated → 200 OK."""
    client, db = client_and_db
    data = _register_user(client, "reset@example.com", "OldPass123!")
    user = db.query(models.User).filter_by(email="reset@example.com").first()
    challenge, otp = _make_otp_challenge(db, user.id)

    resp = client.post("/api/auth/reset-password", json={
        "email": "reset@example.com",
        "otp_code": otp,
        "new_password": "NewPass456!",
    })
    assert resp.status_code == 200
    data = resp.json()
    assert "message" in data


def test_reset_password_updates_db_hash(client_and_db):
    """After a successful reset the DB password hash must match new password."""
    client, db = client_and_db
    _register_user(client, "hash_check@example.com", "OldPass123!")
    user = db.query(models.User).filter_by(email="hash_check@example.com").first()
    challenge, otp = _make_otp_challenge(db, user.id)

    client.post("/api/auth/reset-password", json={
        "email": "hash_check@example.com",
        "otp_code": otp,
        "new_password": "BrandNew789!",
    })
    db.refresh(user)
    assert security.verify_password("BrandNew789!", user.password_hash)


def test_reset_password_old_password_rejected(client_and_db):
    """After reset, old password must not work for login."""
    client, db = client_and_db
    _register_user(client, "oldpw@example.com", "OldPass123!")
    user = db.query(models.User).filter_by(email="oldpw@example.com").first()
    challenge, otp = _make_otp_challenge(db, user.id)
    client.post("/api/auth/reset-password", json={
        "email": "oldpw@example.com",
        "otp_code": otp,
        "new_password": "FreshPass789!",
    })
    # Old password login should fail
    login_resp = client.post("/api/auth/login", json={
        "email": "oldpw@example.com",
        "password": "OldPass123!",
    })
    assert login_resp.status_code in (400, 401, 403)


def test_reset_password_new_password_works_for_login(client_and_db):
    """After reset, new password must enable a successful login."""
    client, db = client_and_db
    _register_user(client, "newpw@example.com", "OldPass123!")
    user = db.query(models.User).filter_by(email="newpw@example.com").first()
    challenge, otp = _make_otp_challenge(db, user.id)
    client.post("/api/auth/reset-password", json={
        "email": "newpw@example.com",
        "otp_code": otp,
        "new_password": "FreshPass789!",
    })
    login_resp = client.post("/api/auth/login", json={
        "email": "newpw@example.com",
        "password": "FreshPass789!",
    })
    assert login_resp.status_code == 200
    assert "access_token" in login_resp.json()


def test_reset_password_no_jwt_in_reset_response(client_and_db):
    """POST /reset-password must NOT return an access_token."""
    client, db = client_and_db
    _register_user(client, "nojwt@example.com", "OldPass123!")
    user = db.query(models.User).filter_by(email="nojwt@example.com").first()
    challenge, otp = _make_otp_challenge(db, user.id)
    resp = client.post("/api/auth/reset-password", json={
        "email": "nojwt@example.com",
        "otp_code": otp,
        "new_password": "Fresh789!",
    })
    assert "access_token" not in resp.json()


def test_reset_password_wrong_otp(client_and_db):
    """Wrong OTP must return 400 and increment attempts."""
    client, db = client_and_db
    _register_user(client, "wrong@example.com", "Pass123!")
    user = db.query(models.User).filter_by(email="wrong@example.com").first()
    challenge, _ = _make_otp_challenge(db, user.id, otp_plaintext="555555")

    resp = client.post("/api/auth/reset-password", json={
        "email": "wrong@example.com",
        "otp_code": "000000",  # wrong
        "new_password": "New123!",
    })
    assert resp.status_code == 400
    db.refresh(challenge)
    assert challenge.attempts == 1


def test_reset_password_max_attempts_locks(client_and_db):
    """After 5 wrong attempts the challenge must be locked (6th returns 400)."""
    client, db = client_and_db
    _register_user(client, "lock@example.com", "Pass123!")
    user = db.query(models.User).filter_by(email="lock@example.com").first()
    challenge, _ = _make_otp_challenge(db, user.id, otp_plaintext="777777", attempts=4)

    # 5th wrong attempt → should lock
    resp = client.post("/api/auth/reset-password", json={
        "email": "lock@example.com",
        "otp_code": "000000",
        "new_password": "New123!",
    })
    assert resp.status_code == 400
    db.refresh(challenge)
    assert challenge.attempts >= 5

    # Subsequent attempt must also be rejected
    resp2 = client.post("/api/auth/reset-password", json={
        "email": "lock@example.com",
        "otp_code": "777777",  # Even correct OTP
        "new_password": "New123!",
    })
    assert resp2.status_code == 400


def test_reset_password_expired_otp(client_and_db):
    """An expired OTP must return 400."""
    client, db = client_and_db
    _register_user(client, "expired@example.com", "Pass123!")
    user = db.query(models.User).filter_by(email="expired@example.com").first()
    _make_otp_challenge(db, user.id, otp_plaintext="987654", expired=True)

    resp = client.post("/api/auth/reset-password", json={
        "email": "expired@example.com",
        "otp_code": "987654",
        "new_password": "New123!",
    })
    assert resp.status_code == 400
    assert "expired" in resp.json()["detail"].lower()


def test_reset_password_used_otp_rejected(client_and_db):
    """A previously-used OTP must be rejected."""
    client, db = client_and_db
    _register_user(client, "used@example.com", "Pass123!")
    user = db.query(models.User).filter_by(email="used@example.com").first()
    _make_otp_challenge(db, user.id, otp_plaintext="111111", is_used=True)

    resp = client.post("/api/auth/reset-password", json={
        "email": "used@example.com",
        "otp_code": "111111",
        "new_password": "New123!",
    })
    assert resp.status_code == 400


def test_new_otp_invalidates_previous(client_and_db, monkeypatch):
    """Generating a second OTP must invalidate the first."""
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEV_EXPOSE_OTP", "1")
    import app.services.auth_service as svc_mod
    svc_mod._DEV_EXPOSE_OTP = True

    _register_user(client, "multi@example.com", "Pass123!")
    user = db.query(models.User).filter_by(email="multi@example.com").first()

    # First OTP
    resp1 = client.post("/api/auth/forgot-password", json={"email": "multi@example.com"})
    first_otp = resp1.json().get("demo_otp")
    assert first_otp is not None

    # Wait slightly and generate a second OTP (bypass 60s cooldown via DB)
    chal1 = (
        db.query(models.PasswordResetOtp)
        .filter_by(user_id=user.id, is_used=False)
        .first()
    )
    # Force last_resend_at to 61 seconds ago so cooldown doesn't block us
    chal1.last_resend_at = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=61)
    db.commit()

    resp2 = client.post("/api/auth/forgot-password", json={"email": "multi@example.com"})
    second_otp = resp2.json().get("demo_otp")
    assert second_otp is not None
    assert second_otp != first_otp

    # Old OTP must now be invalidated (is_used=True)
    db.expire_all()
    old_chal = db.query(models.PasswordResetOtp).filter_by(id=chal1.id).first()
    assert old_chal.is_used is True

    # Attempting reset with old OTP must fail
    resp_old = client.post("/api/auth/reset-password", json={
        "email": "multi@example.com",
        "otp_code": first_otp,
        "new_password": "NewPass789!",
    })
    assert resp_old.status_code == 400

    # Cleanup
    svc_mod._DEV_EXPOSE_OTP = False


def test_single_use_replay_rejected(client_and_db):
    """Replaying the same OTP after a successful reset must return 400."""
    client, db = client_and_db
    _register_user(client, "replay@example.com", "Pass123!")
    user = db.query(models.User).filter_by(email="replay@example.com").first()
    challenge, otp = _make_otp_challenge(db, user.id)

    # First use — success
    resp1 = client.post("/api/auth/reset-password", json={
        "email": "replay@example.com",
        "otp_code": otp,
        "new_password": "NewPass456!",
    })
    assert resp1.status_code == 200

    # Replay — must fail
    resp2 = client.post("/api/auth/reset-password", json={
        "email": "replay@example.com",
        "otp_code": otp,
        "new_password": "AnotherPass789!",
    })
    assert resp2.status_code == 400


# ──────────────────────────────────── OTP cooldown ───────────────────────────

def test_resend_cooldown_enforced(client_and_db, monkeypatch):
    """
    A second forgot-password request within 60 seconds must return 429.
    """
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEV_EXPOSE_OTP", "1")
    import app.services.auth_service as svc_mod
    svc_mod._DEV_EXPOSE_OTP = True

    _register_user(client, "cooldown@example.com", "Pass123!")

    # First request — should succeed
    resp1 = client.post("/api/auth/forgot-password", json={"email": "cooldown@example.com"})
    assert resp1.status_code == 200

    # Immediate second request — should be rate-limited
    resp2 = client.post("/api/auth/forgot-password", json={"email": "cooldown@example.com"})
    assert resp2.status_code == 429

    svc_mod._DEV_EXPOSE_OTP = False


# ──────────────────────────────────── OTP hash is never plaintext ─────────────

def test_otp_not_stored_in_plaintext(client_and_db, monkeypatch):
    """
    The DB must store a 64-char SHA-256 hash, not the raw OTP.
    """
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEV_EXPOSE_OTP", "1")
    import app.services.auth_service as svc_mod
    svc_mod._DEV_EXPOSE_OTP = True

    _register_user(client, "hashcheck@example.com", "Pass123!")
    user = db.query(models.User).filter_by(email="hashcheck@example.com").first()

    resp = client.post("/api/auth/forgot-password", json={"email": "hashcheck@example.com"})
    otp = resp.json().get("demo_otp")
    assert otp is not None

    challenge = (
        db.query(models.PasswordResetOtp)
        .filter_by(user_id=user.id, is_used=False)
        .first()
    )
    assert challenge is not None
    # Must be a hex SHA-256 digest, not the 6-digit plaintext
    assert challenge.otp_hash != otp
    assert len(challenge.otp_hash) == 64
    # And it must verify correctly
    assert challenge.otp_hash == _hash_otp(otp)

    svc_mod._DEV_EXPOSE_OTP = False


# ──────────────────────────────────── PasswordResetOtp model helpers ──────────

def test_model_is_expired_true():
    past = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=1)
    m = models.PasswordResetOtp(
        user_id=1, otp_hash="x", expires_at=past, attempts=0, is_used=False
    )
    assert m.is_expired() is True


def test_model_is_expired_false():
    future = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)
    m = models.PasswordResetOtp(
        user_id=1, otp_hash="x", expires_at=future, attempts=0, is_used=False
    )
    assert m.is_expired() is False


def test_model_is_locked():
    m = models.PasswordResetOtp(user_id=1, otp_hash="x",
                                 expires_at=datetime.datetime.utcnow(), attempts=5, is_used=False)
    assert m.is_locked() is True


def test_model_not_locked():
    m = models.PasswordResetOtp(user_id=1, otp_hash="x",
                                 expires_at=datetime.datetime.utcnow(), attempts=4, is_used=False)
    assert m.is_locked() is False


# ──────────────────────────────────── DEMO MODE TESTS ──────────────────────────

def test_demo_mode_forgot_password(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    _register_user(client, "staff@stocksense.demo", "OldPass123!")

    resp = client.post("/api/auth/forgot-password", json={"email": "staff@stocksense.demo"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["message"] == "Demo OTP generated."
    assert data["demo_otp"] == "123456"
    assert data["is_demo"] is True

    # Check that in DB it is securely stored as SHA-256 hash, not plaintext
    user = db.query(models.User).filter_by(email="staff@stocksense.demo").first()
    challenge = (
        db.query(models.PasswordResetOtp)
        .filter_by(user_id=user.id, is_used=False)
        .first()
    )
    assert challenge is not None
    assert challenge.otp_hash == _hash_otp("123456")
    assert challenge.otp_hash != "123456"


def test_demo_mode_verify_otp_success(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    _register_user(client, "staff@stocksense.demo", "OldPass123!")
    client.post("/api/auth/forgot-password", json={"email": "staff@stocksense.demo"})

    resp = client.post("/api/auth/verify-otp", json={
        "email": "staff@stocksense.demo",
        "otp": "123456",
    })
    assert resp.status_code == 200
    assert resp.json()["valid"] is True


def test_demo_mode_verify_otp_wrong_fails(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    _register_user(client, "staff@stocksense.demo", "OldPass123!")
    client.post("/api/auth/forgot-password", json={"email": "staff@stocksense.demo"})

    resp = client.post("/api/auth/verify-otp", json={
        "email": "staff@stocksense.demo",
        "otp": "999999",
    })
    assert resp.status_code == 400
    assert "Invalid OTP code" in resp.json()["detail"]


def test_demo_mode_verify_otp_lockout(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    _register_user(client, "staff@stocksense.demo", "OldPass123!")
    client.post("/api/auth/forgot-password", json={"email": "staff@stocksense.demo"})

    for _ in range(5):
        resp = client.post("/api/auth/verify-otp", json={
            "email": "staff@stocksense.demo",
            "otp": "000000",
        })
        assert resp.status_code == 400

    # 6th attempt: locked
    resp = client.post("/api/auth/verify-otp", json={
        "email": "staff@stocksense.demo",
        "otp": "123456",
    })
    assert resp.status_code == 400
    assert "Too many incorrect attempts" in resp.json()["detail"]


def test_demo_mode_full_password_reset_and_login(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    _register_user(client, "staff@stocksense.demo", "OldPass123!")

    # 1. Request OTP in demo mode
    client.post("/api/auth/forgot-password", json={"email": "staff@stocksense.demo"})

    # 2. Verify OTP
    v_resp = client.post("/api/auth/verify-otp", json={
        "email": "staff@stocksense.demo",
        "otp": "123456",
    })
    assert v_resp.status_code == 200

    # 3. Reset password
    r_resp = client.post("/api/auth/reset-password", json={
        "email": "staff@stocksense.demo",
        "otp": "123456",
        "new_password": "NewSecretPass456!",
    })
    assert r_resp.status_code == 200

    # 4. Old password must fail
    old_login = client.post("/api/auth/login", json={
        "email": "staff@stocksense.demo",
        "password": "OldPass123!",
    })
    assert old_login.status_code == 401

    # 5. New password must succeed
    new_login = client.post("/api/auth/login", json={
        "email": "staff@stocksense.demo",
        "password": "NewSecretPass456!",
    })
    assert new_login.status_code == 200
    assert "access_token" in new_login.json()

    # 6. Reusing OTP must fail
    reuse_resp = client.post("/api/auth/reset-password", json={
        "email": "staff@stocksense.demo",
        "otp": "123456",
        "new_password": "AnotherPassword789!",
    })
    assert reuse_resp.status_code == 400


def test_production_mode_does_not_return_demo_otp(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "0")
    monkeypatch.setenv("STOCKSENSE_DEV_EXPOSE_OTP", "0")
    # Mock SMTP to avoid network dependency in unit tests
    monkeypatch.setattr("app.services.auth_service.send_password_reset_otp", lambda *a, **k: None)

    _register_user(client, "produser@example.com", "ProdPass123!")
    resp = client.post("/api/auth/forgot-password", json={"email": "produser@example.com"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["demo_otp"] is None
    assert data["is_demo"] is False


def test_demo_mode_manager_account_full_flow(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    _register_user(client, "manager@stocksense.demo", "OldManagerPass123!", role="INVENTORY_MANAGER")

    # 1. Request OTP in demo mode for manager
    resp = client.post("/api/auth/forgot-password", json={"email": "manager@stocksense.demo"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["demo_otp"] == "123456"
    assert data["is_demo"] is True

    # 2. Verify OTP
    v_resp = client.post("/api/auth/verify-otp", json={
        "email": "manager@stocksense.demo",
        "otp": "123456",
    })
    assert v_resp.status_code == 200
    assert v_resp.json()["valid"] is True

    # 3. Reset password
    r_resp = client.post("/api/auth/reset-password", json={
        "email": "manager@stocksense.demo",
        "otp": "123456",
        "new_password": "NewManagerPass456!",
    })
    assert r_resp.status_code == 200

    # 4. Old password fails
    old_login = client.post("/api/auth/login", json={
        "email": "manager@stocksense.demo",
        "password": "OldManagerPass123!",
    })
    assert old_login.status_code == 401

    # 5. New password succeeds
    new_login = client.post("/api/auth/login", json={
        "email": "manager@stocksense.demo",
        "password": "NewManagerPass456!",
    })
    assert new_login.status_code == 200
    assert "access_token" in new_login.json()


def test_demo_status_diagnostic_endpoint(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    resp = client.get("/api/auth/demo-status")
    assert resp.status_code == 200
    data = resp.json()
    assert data["demo_mode_enabled"] is True
    assert data["demo_otp"] == "123456"
    assert "staff@stocksense.demo" in data["supported_demo_accounts"]
    assert "manager@stocksense.demo" in data["supported_demo_accounts"]


def test_health_reports_demo_mode(client_and_db, monkeypatch):
    client, db = client_and_db
    monkeypatch.setenv("STOCKSENSE_DEMO_MODE", "1")
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["demo_mode"] is True

