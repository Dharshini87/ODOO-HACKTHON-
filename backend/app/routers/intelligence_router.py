from typing import List, Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from .. import schemas, auth
from ..database import get_db
from ..services.intelligence_service import IntelligenceService

router = APIRouter(prefix="/intelligence", tags=["Inventory Intelligence"])


@router.get("/stockout", response_model=List[schemas.StockoutItem])
def get_stockout_predictions(
    product_id: Optional[int] = Query(None, description="Optional product ID filter"),
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """
    Section 28: GET /api/intelligence/stockout
    Calculates transparent days to stockout and days to reorder.
    Shows 'Not enough historical movement data.' if insufficient history exists.
    """
    service = IntelligenceService(db)
    return service.get_stockout_predictions(product_id=product_id)


@router.get("/reorder", response_model=List[schemas.ReorderItem])
def get_reorder_recommendations(
    target_coverage: int = Query(30, description="Target coverage in days (default 30)"),
    product_id: Optional[int] = Query(None, description="Optional product ID filter"),
    db: Session = Depends(get_db),
    _=Depends(auth.get_current_user),
):
    """
    Section 28: GET /api/intelligence/reorder
    Provides recommended reorder quantities with transparent calculation explanations.
    """
    service = IntelligenceService(db)
    return service.get_reorder_recommendations(
        target_coverage=target_coverage, product_id=product_id
    )
