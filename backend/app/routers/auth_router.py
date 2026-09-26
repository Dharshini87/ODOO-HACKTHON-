from typing import Union, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..core.dependencies import get_current_user
from ..services.auth_service import AuthService

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

    # Check content-type to parse JSON or form-encoded
    content_type = request.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            body = await request.json()
            email = body.get("email") or body.get("username")
            password = body.get("password")
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid JSON body")
    else:
        # Form encoded
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


@router.post("/forgot-password", response_model=schemas.MessageResponse)
def forgot_password(payload: schemas.ForgotPasswordIn, db: Session = Depends(get_db)):
    """
    Section 5: Forgot password with OTP verification code generation.
    """
    service = AuthService(db)
    otp = service.generate_password_reset_otp(payload.email)
    return schemas.MessageResponse(
        message="If that email is registered, an OTP has been sent.",
        demo_otp=otp,
    )


@router.post("/reset-password", response_model=schemas.MessageResponse)
def reset_password(payload: schemas.ResetPasswordIn, db: Session = Depends(get_db)):
    """
    Section 5: Reset password using verified OTP code.
    """
    service = AuthService(db)
    service.reset_password(
        email=payload.email,
        otp_code=payload.otp_code,
        new_password=payload.new_password,
    )
    return schemas.MessageResponse(message="Password reset successful")


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
