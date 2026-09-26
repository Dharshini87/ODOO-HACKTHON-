from fastapi import HTTPException, status

class StockSenseException(Exception):
    def __init__(self, message: str, status_code: int = status.HTTP_400_BAD_REQUEST):
        self.message = message
        self.status_code = status_code
        super().__init__(self.message)

class InsufficientStockException(StockSenseException):
    def __init__(self, available: float, requested: float, product_name: str = ""):
        super().__init__(
            message=f"Insufficient stock available. On hand: {available}, requested: {requested}",
            status_code=status.HTTP_400_BAD_REQUEST,
        )
        self.available = available
        self.requested = requested

class NotFoundException(StockSenseException):
    def __init__(self, entity: str, identifier: str | int = ""):
        super().__init__(
            message=f"{entity} {identifier} not found".strip(),
            status_code=status.HTTP_404_NOT_FOUND,
        )

class UnauthorizedException(StockSenseException):
    def __init__(self, message: str = "Could not validate credentials"):
        super().__init__(
            message=message,
            status_code=status.HTTP_401_UNAUTHORIZED,
        )
