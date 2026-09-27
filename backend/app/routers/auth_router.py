from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..core.dependencies import get_current_user, require_manager
from ..services.auth_service import AuthService, is_demo_mode, _DEV_EXPOSE_OTP
from ..core.email_service import EmailConfigurationError, EmailDeliveryError

router = APIRouter(tags=["Authentication"])


@router.post("/register", response_model=schemas.Token, status_code=status.HTTP_201_CREATED)
@router.post("/signup", response_model=schemas.Token, status_code=status.HTTP_201_CREATED)
def register(payload: schemas.RegisterIn, db: Session = Depends(get_db)):
    """
    Section 5: Register new user with secure password hashing and role assignment.
    """
    service = AuthService(db)
    user, token = service.register(
        name=payload.name,
        email=payload.email,
        password=payload.password,
        role=payload.role,
    )
    return schemas.Token(
        access_token=token,
        token_type="bearer",
        user_name=user.name,
        role=str(user.role),
        user_id=user.id,
        email=user.email,
        is_manager=user.is_manager,
    )


@router.post("/login", response_model=schemas.Token)
async def login(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Section 5: Login endpoint supporting both JSON payload and OAuth2 form data.
    """
    service = AuthService(db)
    email: Optional[str] = None
    password: Optional[str] = None

    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            body = await request.json()
            email = body.get("email") or body.get("username")
            password = body.get("password")
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid JSON body")
    else:
        try:
            form = await request.form()
            email = form.get("username") or form.get("email")
            password = form.get("password")
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid form body")

    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    user, token = service.authenticate(email=email, password=password)
    return schemas.Token(
        access_token=token,
        token_type="bearer",
        user_name=user.name,
        role=str(user.role),
        user_id=user.id,
        email=user.email,
        is_manager=user.is_manager,
    )


@router.post("/login-json", response_model=schemas.Token)
def login_json(payload: schemas.LoginIn, db: Session = Depends(get_db)):
    """Explicit JSON login route."""
    service = AuthService(db)
    user, token = service.authenticate(email=payload.email, password=payload.password)
    return schemas.Token(
        access_token=token,
        token_type="bearer",
        user_name=user.name,
        role=str(user.role),
        user_id=user.id,
        email=user.email,
        is_manager=user.is_manager,
    )


@router.post("/forgot-password", response_model=schemas.ForgotPasswordResponse)
def forgot_password(payload: schemas.ForgotPasswordIn, db: Session = Depends(get_db)):
    """
    Section 5: Forgot password — generate and deliver a 6-digit OTP.

    When STOCKSENSE_DEMO_MODE=1:
    - Fixed demo OTP 123456 is used.
    - No SMTP delivery is attempted.
    - Returns: {"message": "Demo OTP generated.", "demo_otp": "123456", "is_demo": true}

    When STOCKSENSE_DEMO_MODE=0:
    - Generic message (no email enumeration).
    - OTP is stored only as a SHA-256 hash; plaintext is NEVER returned.
    - STOCKSENSE_DEV_EXPOSE_OTP=1 surfaces OTP for automated CI tests only.
    """
    service = AuthService(db)
    demo_active = is_demo_mode()
    try:
        otp_result = service.generate_password_reset_otp(payload.email)
    except Exception as exc:
        from ..core.exceptions import StockSenseException
        if isinstance(exc, StockSenseException) and exc.status_code == 429:
            raise HTTPException(status_code=429, detail=str(exc.message))
        if isinstance(exc, StockSenseException) and exc.status_code == 503:
            raise HTTPException(status_code=503, detail=str(exc.message))
        otp_result = None

    if demo_active:
        return schemas.ForgotPasswordResponse(
            message="Demo OTP generated.",
            demo_otp=otp_result or "123456",
            is_demo=True,
        )

    return schemas.ForgotPasswordResponse(
        message="If an account exists for this email, an OTP has been sent.",
        demo_otp=otp_result,
        is_demo=False,
    )


@router.post("/verify-otp", response_model=schemas.VerifyOtpResponse)
def verify_otp(payload: schemas.VerifyOtpIn, db: Session = Depends(get_db)):
    """
    Section 5: Verify OTP before resetting password.
    Accepts: email, otp (or otp_code).
    Validates challenge without consuming it (single-use consumed at reset-password).
    """
    service = AuthService(db)
    service.verify_otp(
        email=payload.email,
        otp_code=payload.resolved_otp(),
    )
    return schemas.VerifyOtpResponse(
        message="OTP verified successfully.",
        valid=True,
    )


@router.post("/reset-password", response_model=schemas.MessageResponse)
def reset_password(payload: schemas.ResetPasswordIn, db: Session = Depends(get_db)):
    """
    Section 5: Reset password using verified OTP code.

    Flow:
    1. Find the user by email.
    2. Find the newest unused, non-expired OTP challenge.
    3. Reject if no valid challenge / expired / locked (>= 5 attempts).
    4. Compare supplied OTP against stored hash (constant-time comparison).
    5. If wrong: increment attempts, return safe error.
    6. If correct: atomically update password hash + mark OTP used.
    7. Does NOT issue a new JWT session.
    """
    service = AuthService(db)
    service.reset_password(
        email=payload.email,
        otp_code=payload.resolved_otp(),
        new_password=payload.new_password,
    )
    return schemas.MessageResponse(message="Password reset successful.")


@router.get("/me", response_model=schemas.UserOut)
def get_me(current_user: models.User = Depends(get_current_user)):
    """Get current authenticated user profile & permissions."""
    return schemas.UserOut(
        id=current_user.id,
        name=current_user.name,
        email=current_user.email,
        role=str(current_user.role),
        is_active=current_user.is_active,
        is_manager=current_user.is_manager,
        created_at=current_user.created_at,
    )


@router.get("/system/settings")
@router.get("/settings/system")
def get_auth_system_settings(current_user: models.User = Depends(require_manager)):
    """
    Manager-only access to system & server configuration.
    Staff members receive HTTP 403 Forbidden.
    """
    return {
        "status": "success",
        "system": {
            "project_name": "StockSense",
            "version": "1.0.0",
            "auth_method": "JWT Bearer (HS256)",
            "role_enforcement": "STRICT_DATABASE_RBAC",
            "current_manager": current_user.email,
        }
    }


@router.get("/demo-status")
def demo_status():
    """
    Safe diagnostic endpoint for development and hackathon verification.
    Reports whether demo mode is active and which accounts are supported.
    Does NOT expose any secrets or credentials.
    """
    demo_active = is_demo_mode()
    return {
        "demo_mode_enabled": demo_active,
        "demo_otp_supported": demo_active,
        "demo_otp": "123456" if demo_active else None,
        "supported_demo_accounts": [
            "staff@stocksense.demo",
            "manager@stocksense.demo",
        ],
    }
