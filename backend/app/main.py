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

@app.get("/")
def root():
    return {"message": "StockSense API is running", "docs": "/docs"}

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
