import os
from pathlib import Path
from dotenv import load_dotenv

# Search order for .env:
# 1. backend/.env (directory containing app/)
# 2. stocksense/.env (repo root)
# 3. current working directory
_BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
_REPO_ROOT = _BACKEND_DIR.parent

for _env_file in [
    _BACKEND_DIR / ".env",
    _REPO_ROOT / ".env",
    Path.cwd() / ".env",
]:
    if _env_file.is_file():
        load_dotenv(dotenv_path=_env_file, override=False)


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

    @property
    def DEMO_MODE(self) -> bool:
        return os.getenv("STOCKSENSE_DEMO_MODE", "0").strip().lower() in ("1", "true", "yes")

    DEMO_OTP: str = "123456"


settings = Settings()
