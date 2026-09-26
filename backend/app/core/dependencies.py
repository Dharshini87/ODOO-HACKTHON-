from typing import Optional
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from ..db.session import get_db
from .security import decode_access_token
from .. import models

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)


def get_current_user(
    token: Optional[str] = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> models.User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if not token:
        raise credentials_exception

    payload = decode_access_token(token)
    if payload is None:
        raise credentials_exception

    email: Optional[str] = payload.get("sub")
    if email is None:
        raise credentials_exception

    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None:
        raise credentials_exception

    # Section 43 & 8: Soft deletion check
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account is deactivated",
        )

    return user


def require_role(required_role: str):
    """Require a specific role (or manager)."""
    def role_checker(current_user: models.User = Depends(get_current_user)) -> models.User:
        if current_user.is_manager:
            return current_user
        req_norm = models.Role.normalize(required_role)
        user_norm = models.Role.normalize(current_user.role)
        if user_norm != req_norm:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Operation requires {required_role} role",
            )
        return current_user
    return role_checker


def require_manager(current_user: models.User = Depends(get_current_user)) -> models.User:
    """Enforce INVENTORY_MANAGER role in FastAPI."""
    if not current_user.is_manager:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Operation requires INVENTORY_MANAGER role",
        )
    return current_user


def require_permission(permission_name: str):
    """
    Enforce Section 6 Permissions in FastAPI.
    Frontend visibility is NOT a security mechanism.
    """
    def permission_checker(current_user: models.User = Depends(get_current_user)) -> models.User:
        if not current_user.has_permission(permission_name):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Permission denied: '{permission_name}' requires INVENTORY_MANAGER role",
            )
        return current_user
    return permission_checker


def check_transaction_cancellation_permission(
    created_by_user_id: Optional[int],
    current_user: models.User,
) -> None:
    """
    Section 6 Rule:
    Cancel own transaction: STAFF & MANAGER = YES
    Cancel another user's transaction: STAFF = NO, MANAGER = YES
    """
    if current_user.is_manager:
        return
    if created_by_user_id is not None and created_by_user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Staff members can only cancel their own transactions",
        )
