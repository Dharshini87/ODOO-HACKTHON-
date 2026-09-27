from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..core.dependencies import get_current_user, require_permission

router = APIRouter(prefix="/warehouses", tags=["Warehouses & Locations"])
loc_router = APIRouter(prefix="/locations", tags=["Locations"])


# ============================================================
# HELPER IMPLEMENTATIONS FOR LOCATIONS
# ============================================================

def _list_locations_impl(
    warehouse_id: Optional[int],
    include_inactive: bool,
    db: Session,
) -> List[models.Location]:
    query = db.query(models.Location)
    if not include_inactive:
        query = query.filter(models.Location.is_active == True)
    if warehouse_id is not None:
        query = query.filter(models.Location.warehouse_id == warehouse_id)
    return query.order_by(models.Location.name).all()


def _create_location_impl(
    payload: schemas.LocationIn,
    db: Session,
) -> models.Location:
    # Section 12: Each location belongs to one warehouse
    if payload.warehouse_id is not None:
        wh = db.query(models.Warehouse).filter(models.Warehouse.id == payload.warehouse_id).first()
        if not wh:
            raise HTTPException(status_code=400, detail=f"Warehouse id {payload.warehouse_id} does not exist")

    clean_code = payload.short_code.strip().upper()
    existing = (
        db.query(models.Location)
        .filter(models.Location.warehouse_id == payload.warehouse_id, models.Location.short_code == clean_code)
        .first()
    )
    if existing:
        if not existing.is_active:
            existing.is_active = True
            existing.name = payload.name.strip()
            db.commit()
            db.refresh(existing)
            return existing
        raise HTTPException(
            status_code=400,
            detail=f"Location with short code '{clean_code}' already exists in this warehouse",
        )

    loc = models.Location(
        warehouse_id=payload.warehouse_id,
        name=payload.name.strip(),
        short_code=clean_code,
        is_virtual=payload.is_virtual,
        is_active=payload.is_active,
    )
    db.add(loc)
    db.commit()
    db.refresh(loc)
    return loc


# ============================================================
# 11. WAREHOUSES & LOCATIONS STATIC SUBROUTES
# MUST BE DEFINED BEFORE /{warehouse_id}
# ============================================================

@router.get("", response_model=List[schemas.WarehouseOut])
def list_warehouses(
    include_inactive: bool = Query(False, description="Include soft-deleted warehouses"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Section 6: View Warehouses - STAFF: YES, MANAGER: YES
    """
    query = db.query(models.Warehouse)
    if not include_inactive:
        query = query.filter(models.Warehouse.is_active == True)
    return query.order_by(models.Warehouse.name).all()


@router.post("", response_model=schemas.WarehouseOut, status_code=status.HTTP_201_CREATED)
def create_warehouse(
    payload: schemas.WarehouseIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_warehouses")),
):
    """
    Section 6: Manage Warehouses - STAFF: NO, MANAGER: YES
    Section 11: short_code unique
    """
    clean_code = payload.short_code.strip().upper()
    existing = db.query(models.Warehouse).filter(models.Warehouse.short_code == clean_code).first()
    if existing:
        if not existing.is_active:
            # Reactivate soft-deleted warehouse
            existing.is_active = True
            existing.name = payload.name.strip()
            existing.address = payload.address
            db.commit()
            db.refresh(existing)
            return existing
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Warehouse short code '{clean_code}' already exists",
        )

    wh = models.Warehouse(
        name=payload.name.strip(),
        short_code=clean_code,
        address=payload.address,
        is_active=payload.is_active,
    )
    db.add(wh)
    db.commit()
    db.refresh(wh)
    return wh


# Static subroute for /warehouses/locations (must precede /{warehouse_id})
@router.get("/locations", response_model=List[schemas.LocationOut])
def list_locations_under_warehouses(
    warehouse_id: Optional[int] = Query(None, description="Filter by warehouse ID"),
    include_inactive: bool = Query(False, description="Include soft-deleted locations"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Section 6: View Locations - STAFF: YES, MANAGER: YES
    """
    return _list_locations_impl(warehouse_id, include_inactive, db)


@router.post("/locations", response_model=schemas.LocationOut, status_code=status.HTTP_201_CREATED)
def create_location_under_warehouses(
    payload: schemas.LocationIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_locations")),
):
    """
    Section 6: Manage Locations - STAFF: NO, MANAGER: YES
    Section 12: Each location belongs to one warehouse
    """
    return _create_location_impl(payload, db)


# Parameterized route /{warehouse_id}
@router.get("/{warehouse_id}", response_model=schemas.WarehouseOut)
def get_warehouse(
    warehouse_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    wh = db.query(models.Warehouse).filter(models.Warehouse.id == warehouse_id).first()
    if not wh:
        raise HTTPException(status_code=404, detail="Warehouse not found")
    return wh


@router.put("/{warehouse_id}", response_model=schemas.WarehouseOut)
def update_warehouse(
    warehouse_id: int,
    payload: schemas.WarehouseIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_warehouses")),
):
    """
    Section 6: Manage Warehouses - STAFF: NO, MANAGER: YES
    """
    wh = db.query(models.Warehouse).filter(models.Warehouse.id == warehouse_id).first()
    if not wh:
        raise HTTPException(status_code=404, detail="Warehouse not found")

    clean_code = payload.short_code.strip().upper()
    existing = (
        db.query(models.Warehouse)
        .filter(models.Warehouse.short_code == clean_code, models.Warehouse.id != warehouse_id)
        .first()
    )
    if existing:
        raise HTTPException(status_code=400, detail=f"Short code '{clean_code}' already in use")

    wh.name = payload.name.strip()
    wh.short_code = clean_code
    wh.address = payload.address
    wh.is_active = payload.is_active

    db.commit()
    db.refresh(wh)
    return wh


@router.delete("/{warehouse_id}")
def delete_warehouse(
    warehouse_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_warehouses")),
):
    """
    Section 43: Soft deletion via is_active rather than hard deletion.
    Section 6: Manage Warehouses - STAFF: NO, MANAGER: YES
    """
    wh = db.query(models.Warehouse).filter(models.Warehouse.id == warehouse_id).first()
    if not wh:
        raise HTTPException(status_code=404, detail="Warehouse not found")

    wh.is_active = False
    db.commit()
    return {"message": "Warehouse soft-deleted successfully", "id": warehouse_id}


# ============================================================
# 12. LOCATIONS (DIRECT /locations ROUTER)
# ============================================================

@loc_router.get("", response_model=List[schemas.LocationOut])
def list_locations(
    warehouse_id: Optional[int] = Query(None, description="Filter by warehouse ID"),
    include_inactive: bool = Query(False, description="Include soft-deleted locations"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    return _list_locations_impl(warehouse_id, include_inactive, db)


@loc_router.post("", response_model=schemas.LocationOut, status_code=status.HTTP_201_CREATED)
def create_location(
    payload: schemas.LocationIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_locations")),
):
    return _create_location_impl(payload, db)


@router.put("/locations/{location_id}", response_model=schemas.LocationOut)
@loc_router.put("/{location_id}", response_model=schemas.LocationOut)
def update_location(
    location_id: int,
    payload: schemas.LocationIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_locations")),
):
    """
    Section 6: Manage Locations - STAFF: NO, MANAGER: YES
    """
    loc = db.query(models.Location).filter(models.Location.id == location_id).first()
    if not loc:
        raise HTTPException(status_code=404, detail="Location not found")

    if payload.warehouse_id is not None:
        wh = db.query(models.Warehouse).filter(models.Warehouse.id == payload.warehouse_id).first()
        if not wh:
            raise HTTPException(status_code=400, detail="Warehouse does not exist")

    clean_code = payload.short_code.strip().upper()
    existing = (
        db.query(models.Location)
        .filter(
            models.Location.warehouse_id == payload.warehouse_id,
            models.Location.short_code == clean_code,
            models.Location.id != location_id,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=400, detail=f"Location '{clean_code}' already exists in this warehouse")

    loc.warehouse_id = payload.warehouse_id
    loc.name = payload.name.strip()
    loc.short_code = clean_code
    loc.is_virtual = payload.is_virtual
    loc.is_active = payload.is_active

    db.commit()
    db.refresh(loc)
    return loc


@router.delete("/locations/{location_id}")
@loc_router.delete("/{location_id}")
def delete_location(

    location_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_locations")),
):
    """
    Section 43: Soft deletion via is_active rather than hard deletion.
    Section 6: Manage Locations - STAFF: NO, MANAGER: YES
    """
    loc = db.query(models.Location).filter(models.Location.id == location_id).first()
    if not loc:
        raise HTTPException(status_code=404, detail="Location not found")

    loc.is_active = False
    db.commit()
    return {"message": "Location soft-deleted successfully", "id": location_id}
