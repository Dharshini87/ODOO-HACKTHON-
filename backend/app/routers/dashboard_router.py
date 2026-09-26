from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from .. import schemas, auth
from ..database import get_db
from ..services.dashboard_service import DashboardService

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


@router.get("/summary", response_model=schemas.DashboardSummaryOut)
def get_dashboard_summary(
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """
    Section 26: GET /api/dashboard/summary
    Database-driven dashboard metrics, low-stock products, recent movements, and intelligence preview.
    Never hardcode dashboard numbers.
    """
    service = DashboardService(db)
    return service.get_dashboard_summary()


@router.get("", response_model=schemas.DashboardSummaryOut)
def get_dashboard(
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """
    Convenience alias for /dashboard and backward compatibility.
    """
    service = DashboardService(db)
    return service.get_dashboard_summary()
