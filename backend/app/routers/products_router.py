from typing import List, Optional
from decimal import Decimal
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from .. import models, schemas
from ..database import get_db
from ..core.dependencies import get_current_user, require_permission

router = APIRouter(prefix="/products", tags=["Products"])
cat_router = APIRouter(prefix="/categories", tags=["Categories"])


# ============================================================
# 9. CATEGORIES
# ============================================================

@cat_router.get("", response_model=List[schemas.CategoryOut])
def list_categories(
    include_inactive: bool = Query(False, description="Include soft-deleted categories"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Section 6: View Products/Categories - STAFF: YES, MANAGER: YES
    """
    query = db.query(models.Category)
    if not include_inactive:
        query = query.filter(models.Category.is_active == True)
    return query.order_by(models.Category.name).all()


@cat_router.post("", response_model=schemas.CategoryOut, status_code=status.HTTP_201_CREATED)
def create_category(
    payload: schemas.CategoryIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_categories")),
):
    """
    Section 6: Manage Categories - STAFF: NO, MANAGER: YES
    Section 9: Category name should be unique.
    """
    clean_name = payload.name.strip()
    existing = db.query(models.Category).filter(models.Category.name.ilike(clean_name)).first()
    if existing:
        if not existing.is_active:
            # Reactivate previously soft-deleted category
            existing.is_active = True
            existing.description = payload.description or existing.description
            db.commit()
            db.refresh(existing)
            return existing
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Category with name '{clean_name}' already exists",
        )

    cat = models.Category(
        name=clean_name,
        description=payload.description,
        is_active=payload.is_active,
    )
    db.add(cat)
    db.commit()
    db.refresh(cat)
    return cat


@cat_router.put("/{category_id}", response_model=schemas.CategoryOut)
def update_category(
    category_id: int,
    payload: schemas.CategoryIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_categories")),
):
    """
    Section 6: Manage Categories - STAFF: NO, MANAGER: YES
    """
    cat = db.query(models.Category).filter(models.Category.id == category_id).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")

    clean_name = payload.name.strip()
    existing = (
        db.query(models.Category)
        .filter(models.Category.name.ilike(clean_name), models.Category.id != category_id)
        .first()
    )
    if existing:
        raise HTTPException(status_code=400, detail=f"Category '{clean_name}' already exists")

    cat.name = clean_name
    if payload.description is not None:
        cat.description = payload.description
    cat.is_active = payload.is_active
    db.commit()
    db.refresh(cat)
    return cat


@cat_router.delete("/{category_id}")
def delete_category(
    category_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_categories")),
):
    """
    Section 43: Soft deletion via is_active rather than hard deletion.
    Section 6: Manage Categories - STAFF: NO, MANAGER: YES
    """
    cat = db.query(models.Category).filter(models.Category.id == category_id).first()
    if not cat:
        raise HTTPException(status_code=404, detail="Category not found")

    # Soft deletion
    cat.is_active = False
    db.commit()
    return {"message": "Category soft-deleted successfully", "id": category_id}


# ============================================================
# 10. PRODUCTS
# ============================================================

@router.get("", response_model=List[schemas.ProductOut])
def list_products(
    category_id: Optional[int] = Query(None, description="Filter by category ID"),
    search: Optional[str] = Query(None, description="Search by name or SKU"),
    include_inactive: bool = Query(False, description="Include soft-deleted products"),
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    """
    Section 6: View Products - STAFF: YES, MANAGER: YES
    """
    query = db.query(models.Product)
    if not include_inactive:
        query = query.filter(models.Product.is_active == True)
    if category_id is not None:
        query = query.filter(models.Product.category_id == category_id)
    if search:
        s = f"%{search.strip()}%"
        query = query.filter((models.Product.name.ilike(s)) | (models.Product.sku.ilike(s)))

    return query.order_by(models.Product.name).all()


@router.get("/{product_id}", response_model=schemas.ProductOut)
def get_product(
    product_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(get_current_user),
):
    product = db.query(models.Product).filter(models.Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.post("", response_model=schemas.ProductOut, status_code=status.HTTP_201_CREATED)
def create_product(
    payload: schemas.ProductIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_products")),
):
    """
    Section 6: Manage Products - STAFF: NO, MANAGER: YES
    Section 10 Constraints:
      - SKU unique
      - reorder_level >= 0
      - Use NUMERIC for monetary and quantity values
    """
    clean_sku = payload.sku.strip().upper()
    existing = db.query(models.Product).filter(models.Product.sku == clean_sku).first()
    if existing:
        if not existing.is_active:
            # Reactivate soft-deleted product with new attributes
            existing.is_active = True
            existing.name = payload.name.strip()
            existing.category_id = payload.category_id
            existing.unit_of_measure = payload.unit_of_measure
            cost = payload.unit_cost if payload.unit_cost is not None else payload.cost_per_unit
            reorder = payload.reorder_level if payload.reorder_level is not None else payload.reorder_point
            if reorder is not None and reorder < 0:
                raise HTTPException(status_code=400, detail="reorder_level must be >= 0")
            existing.cost_per_unit = Decimal(str(cost or 0.0))
            existing.reorder_point = Decimal(str(reorder or 0.0))
            db.commit()
            db.refresh(existing)
            return existing
        raise HTTPException(status_code=400, detail=f"Product SKU '{clean_sku}' already exists")

    # Validate category exists if provided
    if payload.category_id is not None:
        cat = db.query(models.Category).filter(models.Category.id == payload.category_id).first()
        if not cat:
            raise HTTPException(status_code=400, detail="Category does not exist")

    # Reorder level >= 0 check
    reorder = payload.reorder_level if payload.reorder_level is not None else payload.reorder_point
    if reorder is not None and reorder < 0:
        raise HTTPException(status_code=400, detail="reorder_level must be >= 0")

    cost = payload.unit_cost if payload.unit_cost is not None else payload.cost_per_unit
    product = models.Product(
        name=payload.name.strip(),
        sku=clean_sku,
        category_id=payload.category_id,
        unit_of_measure=payload.unit_of_measure or "unit",
        cost_per_unit=Decimal(str(cost or 0.0)),
        reorder_point=Decimal(str(reorder or 0.0)),
        is_active=payload.is_active,
    )
    db.add(product)
    db.commit()
    db.refresh(product)
    return product


@router.put("/{product_id}", response_model=schemas.ProductOut)
def update_product(
    product_id: int,
    payload: schemas.ProductIn,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_products")),
):
    """
    Section 6: Manage Products - STAFF: NO, MANAGER: YES
    """
    product = db.query(models.Product).filter(models.Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    clean_sku = payload.sku.strip().upper()
    existing = (
        db.query(models.Product)
        .filter(models.Product.sku == clean_sku, models.Product.id != product_id)
        .first()
    )
    if existing:
        raise HTTPException(status_code=400, detail=f"Product SKU '{clean_sku}' already exists")

    reorder = payload.reorder_level if payload.reorder_level is not None else payload.reorder_point
    if reorder is not None and reorder < 0:
        raise HTTPException(status_code=400, detail="reorder_level must be >= 0")

    cost = payload.unit_cost if payload.unit_cost is not None else payload.cost_per_unit

    product.name = payload.name.strip()
    product.sku = clean_sku
    product.category_id = payload.category_id
    product.unit_of_measure = payload.unit_of_measure
    if cost is not None:
        product.cost_per_unit = Decimal(str(cost))
    if reorder is not None:
        product.reorder_point = Decimal(str(reorder))
    product.is_active = payload.is_active

    db.commit()
    db.refresh(product)
    return product


@router.delete("/{product_id}")
def delete_product(
    product_id: int,
    db: Session = Depends(get_db),
    _: models.User = Depends(require_permission("manage_products")),
):
    """
    Section 43: Soft deletion via is_active rather than hard deletion.
    Section 6: Manage Products - STAFF: NO, MANAGER: YES
    """
    product = db.query(models.Product).filter(models.Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    product.is_active = False
    db.commit()
    return {"message": "Product soft-deleted successfully", "id": product_id}
