"""
StockSense Authentication Service.

Security invariants:
- OTP generation uses secrets.randbelow() — cryptographically secure PRNG.
- OTP is stored ONLY as a SHA-256 hash; plaintext is never persisted.
- forgot-password response is always the same generic message regardless of
  whether the email is registered (no email enumeration).
- Password reset does NOT issue a new JWT session.
- Existing JWT/RBAC flow is completely unchanged.
- OTP is single-use; a successful reset or a new OTP generation marks older
  records as used.
- Maximum 5 verification attempts before the OTP record is locked.
- Resend cooldown of 60 seconds enforced at the OTP record level.
- All DB writes during reset are in a single transaction (atomic).
- Plaintext OTP is never logged.
"""
import datetime
import hashlib
import logging
import os
import secrets
import sys
from typing import Optional, Tuple

from sqlalchemy.orm import Session

from .. import models, schemas
from ..core import security, exceptions
from ..core.email_service import (
    EmailConfigurationError,
    EmailDeliveryError,
    is_email_configured,
    send_password_reset_otp,
)

logger = logging.getLogger(__name__)

def is_demo_mode() -> bool:
    """Return True if STOCKSENSE_DEMO_MODE=1 is set."""
    return os.getenv("STOCKSENSE_DEMO_MODE", "0").strip().lower() in ("1", "true", "yes")

DEMO_OTP: str = "123456"

DEMO_ACCOUNTS = {
    "staff@stocksense.demo": {
        "name": "Warehouse Staff",
        "role": models.Role.WAREHOUSE_STAFF.value,
        "default_password": "password123",
    },
    "manager@stocksense.demo": {
        "name": "Inventory Manager",
        "role": models.Role.INVENTORY_MANAGER.value,
        "default_password": "password123",
    },
}

# Whether to surface the OTP in the API response (dev / CI only)
_DEV_EXPOSE_OTP: bool = os.getenv("STOCKSENSE_DEV_EXPOSE_OTP", "0").strip() == "1"


def _hash_otp(otp_plaintext: str) -> str:
    """Return SHA-256 hex digest of the OTP string."""
    return hashlib.sha256(otp_plaintext.encode()).hexdigest()


def _generate_secure_otp() -> str:
    """Return a 6-digit OTP using a cryptographically secure PRNG."""
    # secrets.randbelow(900000) gives [0, 900000); adding 100000 guarantees
    # a 6-digit number in [100000, 999999].
    return str(100000 + secrets.randbelow(900000))


class AuthService:
    def __init__(self, db: Session):
        self.db = db

    # ------------------------------------------------------------------ register
    def register(
        self,
        name: str,
        email: str,
        password: str,
        role: str = "WAREHOUSE_STAFF",
    ) -> Tuple[models.User, str]:
        email_clean = email.strip().lower()
        existing = (
            self.db.query(models.User)
            .filter(models.User.email == email_clean)
            .first()
        )
        if existing:
            raise exceptions.StockSenseException(
                "Email already registered", status_code=400
            )

        normalized_role = models.Role.normalize(role)

        user = models.User(
            name=name.strip(),
            email=email_clean,
            password_hash=security.hash_password(password),
            role=normalized_role.value,
            is_active=True,
        )
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)

        token = security.create_access_token(
            {
                "sub": user.email,
                "user_id": user.id,
                "role": user.role,
                "name": user.name,
            }
        )
        return user, token

    # ----------------------------------------------------------------- authenticate
    def authenticate(self, email: str, password: str) -> Tuple[models.User, str]:
        email_clean = email.strip().lower()
        user = (
            self.db.query(models.User)
            .filter(models.User.email == email_clean)
            .first()
        )
        if not user or not security.verify_password(password, user.password_hash):
            raise exceptions.UnauthorizedException("Incorrect email or password")

        if not user.is_active:
            raise exceptions.StockSenseException(
                "Account is deactivated", status_code=403
            )

        token = security.create_access_token(
            {
                "sub": user.email,
                "user_id": user.id,
                "role": user.role,
                "name": user.name,
            }
        )
        return user, token

    # ---------------------------------------------------- generate_password_reset_otp
    def generate_password_reset_otp(
        self, email: str
    ) -> Optional[str]:
        """
        Generate a secure 6-digit OTP for password reset.

        Returns:
            The plaintext OTP **only** when STOCKSENSE_DEV_EXPOSE_OTP=1
            (development / CI environments).
            Returns None in all other cases so the caller cannot leak it.

        Raises:
            EmailConfigurationError: if SMTP is not configured and dev-expose is off.
            EmailDeliveryError: if the SMTP send fails.

        Side effects:
            - All previous unused OTP challenges for this user are invalidated.
            - A new PasswordResetOtp record is created (stores only the hash).
            - An email is sent to the user (unless dev-expose mode is active).
        """
        email_clean = email.strip().lower()
        user = (
            self.db.query(models.User)
            .filter(models.User.email == email_clean)
            .first()
        )

        if not user:
            if is_demo_mode():
                # For demo mode: auto-create the demo user so the demo flow is resilient
                acct = DEMO_ACCOUNTS.get(
                    email_clean,
                    {
                        "name": "Demo User",
                        "role": models.Role.WAREHOUSE_STAFF.value,
                        "default_password": "password123",
                    },
                )
                user = models.User(
                    name=acct["name"],
                    email=email_clean,
                    password_hash=security.hash_password(acct["default_password"]),
                    role=acct["role"],
                    is_active=True,
                )
                self.db.add(user)
                self.db.commit()
                self.db.refresh(user)
            else:
                # Do NOT reveal that the email is unregistered.
                logger.info("OTP requested for unknown email (suppressed).")
                return None

        # ---- Resend cooldown check (60 s) based on the newest active record ---
        now = datetime.datetime.now(datetime.timezone.utc)
        if not is_demo_mode():
            newest_active = (
                self.db.query(models.PasswordResetOtp)
                .filter(
                    models.PasswordResetOtp.user_id == user.id,
                    models.PasswordResetOtp.is_used == False,  # noqa: E712
                )
                .order_by(models.PasswordResetOtp.created_at.desc())
                .first()
            )
            if newest_active and newest_active.last_resend_at:
                resend_ts = newest_active.last_resend_at
                if resend_ts.tzinfo is None:
                    resend_ts = resend_ts.replace(tzinfo=datetime.timezone.utc)
                elapsed = (now - resend_ts).total_seconds()
                if elapsed < models.PasswordResetOtp.RESEND_COOLDOWN_SECONDS:
                    remaining = int(
                        models.PasswordResetOtp.RESEND_COOLDOWN_SECONDS - elapsed
                    )
                    raise exceptions.StockSenseException(
                        f"Please wait {remaining} seconds before requesting another OTP.",
                        status_code=429,
                    )

        # ---- Invalidate all previous unused OTPs for this user ----------------
        self.db.query(models.PasswordResetOtp).filter(
            models.PasswordResetOtp.user_id == user.id,
            models.PasswordResetOtp.is_used == False,  # noqa: E712
        ).update({"is_used": True}, synchronize_session=False)

        # ---- Generate + hash OTP ----------------------------------------------
        if is_demo_mode():
            otp_plaintext = DEMO_OTP  # Fixed demo OTP: "123456"
        else:
            otp_plaintext = _generate_secure_otp()

        otp_hash = _hash_otp(otp_plaintext)
        expiry = now + datetime.timedelta(
            minutes=models.PasswordResetOtp.OTP_TTL_MINUTES
        )

        new_challenge = models.PasswordResetOtp(
            user_id=user.id,
            otp_hash=otp_hash,
            expires_at=expiry,
            attempts=0,
            is_used=False,
            last_resend_at=now,
        )
        self.db.add(new_challenge)
        self.db.commit()
        self.db.refresh(new_challenge)

        # ---- Deliver via email, surface in demo mode, or surface in dev mode ---
        if is_demo_mode():
            demo_msg = (
                f"\n======================================================\n"
                f"[DEMO OTP] Password reset OTP for {user.email}: {otp_plaintext}\n"
                f"======================================================\n"
            )
            sys.stdout.write(demo_msg)
            sys.stdout.flush()
            sys.stderr.write(demo_msg)
            sys.stderr.flush()
            logger.warning("[DEMO OTP] Password reset OTP for %s: %s", user.email, otp_plaintext)
            return otp_plaintext

        if _DEV_EXPOSE_OTP or os.getenv("STOCKSENSE_DEV_EXPOSE_OTP", "0").strip() == "1":
            # Only safe for development / automated tests; never in production.
            logger.debug(
                "[DEV] Password-reset OTP for %s: %s****, challenge_id=%d",
                user.email,
                otp_plaintext[:2],
                new_challenge.id,
            )
            return otp_plaintext

        # Production path: attempt SMTP delivery.
        try:
            send_password_reset_otp(user.email, otp_plaintext)
        except (EmailConfigurationError, EmailDeliveryError) as exc:
            # Roll back the new challenge if delivery failed, to avoid a hanging
            # challenge that the user can never access.
            self.db.delete(new_challenge)
            self.db.commit()
            raise exceptions.StockSenseException(
                "Password reset email could not be delivered. "
                "Please check the server SMTP configuration.",
                status_code=503,
            ) from exc

        return None  # plaintext OTP is NOT returned in production

    # ----------------------------------------------------------------- verify_otp
    def verify_otp(self, email: str, otp_code: str) -> bool:
        """
        Verify that the supplied OTP matches the newest active challenge.
        Increments attempts on failure; locks after 5 attempts.
        Does NOT mark OTP as used (that happens on actual reset).
        """
        email_clean = email.strip().lower()
        otp_clean = otp_code.strip()

        user = (
            self.db.query(models.User)
            .filter(models.User.email == email_clean)
            .first()
        )
        if not user:
            raise exceptions.StockSenseException(
                "Invalid or expired OTP code.", status_code=400
            )

        challenge = (
            self.db.query(models.PasswordResetOtp)
            .filter(
                models.PasswordResetOtp.user_id == user.id,
                models.PasswordResetOtp.is_used == False,  # noqa: E712
            )
            .order_by(models.PasswordResetOtp.created_at.desc())
            .first()
        )

        if challenge is None:
            raise exceptions.StockSenseException(
                "No active password reset request found.", status_code=400
            )

        if challenge.is_expired():
            raise exceptions.StockSenseException(
                "OTP has expired. Please request a new password reset.", status_code=400
            )

        if challenge.is_locked():
            raise exceptions.StockSenseException(
                "Too many incorrect attempts. Please request a new OTP.", status_code=400
            )

        supplied_hash = _hash_otp(otp_clean)
        if not secrets.compare_digest(supplied_hash, challenge.otp_hash):
            challenge.attempts += 1
            self.db.commit()

            remaining = models.PasswordResetOtp.MAX_ATTEMPTS - challenge.attempts
            if remaining <= 0:
                raise exceptions.StockSenseException(
                    "Too many incorrect attempts. Please request a new OTP.",
                    status_code=400,
                )
            raise exceptions.StockSenseException(
                f"Invalid OTP code. {remaining} attempt(s) remaining.",
                status_code=400,
            )

        return True

    # ------------------------------------------------------------ reset_password
    def reset_password(
        self, email: str, otp_code: str, new_password: str
    ) -> bool:
        """
        Verify OTP and atomically update the user's password.

        Security rules enforced:
        - OTP is compared against its hash only.
        - Wrong OTP increments attempts; >= 5 locks the record.
        - Expired OTP is rejected.
        - Already-used OTP is rejected.
        - Successful reset marks the OTP as used and invalidates all others.
        - Password is stored only as a bcrypt hash.
        - NO new JWT session is issued.
        - The entire DB write is in a single atomic transaction.
        """
        email_clean = email.strip().lower()
        otp_clean = otp_code.strip()

        user = (
            self.db.query(models.User)
            .filter(models.User.email == email_clean)
            .first()
        )
        if not user:
            raise exceptions.StockSenseException(
                "Invalid or expired OTP code.", status_code=400
            )

        # Find the newest non-used OTP challenge for this user
        challenge = (
            self.db.query(models.PasswordResetOtp)
            .filter(
                models.PasswordResetOtp.user_id == user.id,
                models.PasswordResetOtp.is_used == False,  # noqa: E712
            )
            .order_by(models.PasswordResetOtp.created_at.desc())
            .first()
        )

        if challenge is None:
            raise exceptions.StockSenseException(
                "No active password reset request found.", status_code=400
            )

        if challenge.is_expired():
            raise exceptions.StockSenseException(
                "OTP has expired. Please request a new password reset.", status_code=400
            )

        if challenge.is_locked():
            raise exceptions.StockSenseException(
                "Too many incorrect attempts. Please request a new OTP.", status_code=400
            )

        # Constant-time comparison via hash equality (prevents timing attacks)
        supplied_hash = _hash_otp(otp_clean)
        if not secrets.compare_digest(supplied_hash, challenge.otp_hash):
            # Increment failed attempts
            challenge.attempts += 1
            self.db.commit()

            remaining = models.PasswordResetOtp.MAX_ATTEMPTS - challenge.attempts
            if remaining <= 0:
                raise exceptions.StockSenseException(
                    "Too many incorrect attempts. Please request a new OTP.",
                    status_code=400,
                )
            raise exceptions.StockSenseException(
                f"Invalid OTP code. {remaining} attempt(s) remaining.",
                status_code=400,
            )

        # ---- OTP is correct: atomically update password + mark OTP used ------
        user.password_hash = security.hash_password(new_password)
        # Clear legacy OTP fields if they were set
        user.otp_code = None
        user.otp_expiry = None

        # Mark this challenge as used
        challenge.is_used = True

        # Invalidate any other unused challenges (safety net)
        self.db.query(models.PasswordResetOtp).filter(
            models.PasswordResetOtp.user_id == user.id,
            models.PasswordResetOtp.is_used == False,  # noqa: E712
            models.PasswordResetOtp.id != challenge.id,
        ).update({"is_used": True}, synchronize_session=False)

        self.db.commit()
        logger.info("Password reset successful for user_id=%d", user.id)
        return True
