from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .database import engine, Base
from .routers import (
    auth_router,
    products_router,
    warehouses_router,
    receipts_router,
    deliveries_router,
    transfers_router,
    adjustments_router,
    stock_router,
    move_history_router,
    dashboard_router,
    transactions_router,
    intelligence_router,
    moves_router,
    demo_router,
    receipt_verification_router,
)

Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="StockSense API",
    description="Ledger-based Inventory Management System",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from fastapi.responses import JSONResponse
from .core.exceptions import StockSenseException

@app.exception_handler(StockSenseException)
def stocksense_exception_handler(request, exc: StockSenseException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.message},
    )

app.include_router(auth_router.router, prefix="/api/auth", tags=["Authentication"])
app.include_router(auth_router.router, prefix="/auth", tags=["Authentication"])
# Master Data & Core Routes
app.include_router(products_router.router)
app.include_router(products_router.router, prefix="/api")
app.include_router(products_router.cat_router)
app.include_router(products_router.cat_router, prefix="/api")
app.include_router(warehouses_router.router)
app.include_router(warehouses_router.router, prefix="/api")
app.include_router(warehouses_router.loc_router)
app.include_router(warehouses_router.loc_router, prefix="/api")

# Unified Transactions & Inventory Engine (Sections 14, 18, 40, 41)
app.include_router(transactions_router.router)
app.include_router(transactions_router.router, prefix="/api")

# Inventory, Operations, Ledger & Dashboard
app.include_router(receipts_router.router)
app.include_router(receipts_router.router, prefix="/api")
app.include_router(deliveries_router.router)
app.include_router(deliveries_router.router, prefix="/api")
app.include_router(transfers_router.router)
app.include_router(transfers_router.router, prefix="/api")
app.include_router(adjustments_router.router)
app.include_router(adjustments_router.router, prefix="/api")
app.include_router(stock_router.router)
app.include_router(stock_router.router, prefix="/api")
app.include_router(move_history_router.router)
app.include_router(move_history_router.router, prefix="/api")
app.include_router(dashboard_router.router)
app.include_router(dashboard_router.router, prefix="/api")
app.include_router(intelligence_router.router)
app.include_router(intelligence_router.router, prefix="/api")
app.include_router(moves_router.router)
app.include_router(moves_router.router, prefix="/api")
app.include_router(demo_router.router)
app.include_router(demo_router.router, prefix="/api")
app.include_router(receipt_verification_router.router)
app.include_router(receipt_verification_router.router, prefix="/api")


from sqlalchemy import text
from .database import get_db
from sqlalchemy.orm import Session
from fastapi import Depends
from .core.dependencies import require_manager, get_current_user
from . import models

@app.get("/system/settings", tags=["System Settings"])
@app.get("/api/system/settings", tags=["System Settings"])
@app.get("/settings/system", tags=["System Settings"])
@app.get("/api/settings/system", tags=["System Settings"])
def get_system_settings(current_user: models.User = Depends(require_manager)):
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
        },
    }

@app.get("/notifications", tags=["Notifications"])
@app.get("/api/notifications", tags=["Notifications"])
def get_notifications(current_user: models.User = Depends(get_current_user)):
    """
    View notifications (Staff & Manager allowed).
    """
    return {
        "status": "success",
        "notifications": [],
    }

@app.get("/")
def root():
    return {"message": "StockSense API is running", "docs": "/docs"}

import os
from fastapi import Response, status
from fastapi.responses import FileResponse

_FAVICON_PATH = os.path.join(os.path.dirname(__file__), "favicon.png")

@app.get("/favicon.ico", include_in_schema=False)
@app.get("/favicon.png", include_in_schema=False)
def favicon():
    if os.path.exists(_FAVICON_PATH):
        return FileResponse(_FAVICON_PATH, media_type="image/png")
    return Response(status_code=status.HTTP_204_NO_CONTENT)

@app.get("/health")

def health(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception as e:
        db_status = f"unhealthy: {str(e)}"
    return {
        "status": "healthy" if db_status == "connected" else "degraded",
        "service": "stocksense-api",
        "version": "1.0.0",
        "database": db_status,
    }
