import datetime
import random
from typing import Optional, Tuple
from sqlalchemy.orm import Session
from .. import models, schemas
from ..core import security, exceptions


class AuthService:
    def __init__(self, db: Session):
        self.db = db

    def register(
        self,
        name: str,
        email: str,
        password: str,
        role: str = "WAREHOUSE_STAFF",
    ) -> Tuple[models.User, str]:
        email_clean = email.strip().lower()
        existing = self.db.query(models.User).filter(models.User.email == email_clean).first()
        if existing:
            raise exceptions.StockSenseException("Email already registered", status_code=400)

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

        token = security.create_access_token({
            "sub": user.email,
            "user_id": user.id,
            "role": user.role,
            "name": user.name,
        })
        return user, token

    def authenticate(self, email: str, password: str) -> Tuple[models.User, str]:
        email_clean = email.strip().lower()
        user = self.db.query(models.User).filter(models.User.email == email_clean).first()
        if not user or not security.verify_password(password, user.password_hash):
            raise exceptions.UnauthorizedException("Incorrect email or password")

        if not user.is_active:
            raise exceptions.StockSenseException("Account is deactivated", status_code=403)

        token = security.create_access_token({
            "sub": user.email,
            "user_id": user.id,
            "role": user.role,
            "name": user.name,
        })
        return user, token

    def generate_password_reset_otp(self, email: str) -> Optional[str]:
        email_clean = email.strip().lower()
        user = self.db.query(models.User).filter(models.User.email == email_clean).first()
        if not user:
            return None

        otp = f"{random.randint(100000, 999999)}"
        expiry = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=15)

        # Update user entity
        user.otp_code = otp
        user.otp_expiry = expiry

        # Record in password_reset_tokens table (Section 7)
        token_entry = models.PasswordResetToken(
            user_id=user.id,
            token=f"reset-{otp}-{int(datetime.datetime.now().timestamp())}",
            otp_code=otp,
            expires_at=expiry,
            is_used=False,
        )
        self.db.add(token_entry)
        self.db.commit()

        # In production this sends via SMTP/SMS; in dev we log to console
        print(f"\n[StockSense OTP] Password reset OTP for {user.email}: {otp}\n")
        return otp

    def reset_password(self, email: str, otp_code: str, new_password: str) -> bool:
        email_clean = email.strip().lower()
        user = self.db.query(models.User).filter(models.User.email == email_clean).first()
        if not user:
            raise exceptions.StockSenseException("Invalid email or reset request", status_code=400)

        # Helper for naive/aware timezone comparison
        def _not_expired(dt) -> bool:
            if not dt:
                return False
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=datetime.timezone.utc)
            return dt > datetime.datetime.now(datetime.timezone.utc)

        token_record = (
            self.db.query(models.PasswordResetToken)
            .filter(
                models.PasswordResetToken.user_id == user.id,
                models.PasswordResetToken.otp_code == otp_code.strip(),
                models.PasswordResetToken.is_used == False,
            )
            .order_by(models.PasswordResetToken.id.desc())
            .first()
        )

        valid_token = token_record and _not_expired(token_record.expires_at)
        valid_user_otp = user.otp_code and user.otp_code == otp_code.strip() and _not_expired(user.otp_expiry)

        if not valid_token and not valid_user_otp:
            raise exceptions.StockSenseException("Invalid or expired OTP code", status_code=400)

        # Update user password
        user.password_hash = security.hash_password(new_password)
        user.otp_code = None
        user.otp_expiry = None

        if token_record:
            token_record.is_used = True

        self.db.commit()
        return True
