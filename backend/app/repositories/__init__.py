from sqlalchemy.orm import Session
from .. import models

class BaseRepository:
    def __init__(self, db: Session):
        self.db = db

class ProductRepository(BaseRepository):
    def get_by_id(self, product_id: int):
        return self.db.query(models.Product).get(product_id)

    def get_by_sku(self, sku: str):
        return self.db.query(models.Product).filter(models.Product.sku == sku).first()

    def get_all(self):
        return self.db.query(models.Product).all()

class WarehouseRepository(BaseRepository):
    def get_by_id(self, warehouse_id: int):
        return self.db.query(models.Warehouse).get(warehouse_id)

    def get_all(self):
        return self.db.query(models.Warehouse).all()

class LocationRepository(BaseRepository):
    def get_by_id(self, location_id: int):
        return self.db.query(models.Location).get(location_id)

    def get_all(self):
        return self.db.query(models.Location).filter(models.Location.is_virtual == False).all()

class StockMoveRepository(BaseRepository):
    def get_by_id(self, move_id: int):
        return self.db.query(models.StockMove).get(move_id)

    def get_by_reference(self, reference: str):
        return self.db.query(models.StockMove).filter(models.StockMove.reference == reference).first()
