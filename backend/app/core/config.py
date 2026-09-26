import os

class Settings:
    PROJECT_NAME: str = "StockSense"
    VERSION: str = "1.0.0"
    API_V1_STR: str = ""
    
    SECRET_KEY: str = os.getenv("SECRET_KEY", "stocksense-hackathon-secret-change-in-production")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 12  # 12 hours
    
    # Authoritative DB connection string: PostgreSQL in production, SQLite fallback
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./stocksense.db")
    
    CORS_ORIGINS: list[str] = ["*"]

settings = Settings()
