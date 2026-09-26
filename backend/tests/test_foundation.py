import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.core import security, config

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "stocksense-api"
    assert data["database"] == "connected"

def test_root_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "StockSense API is running" in data["message"]

def test_password_hashing():
    pwd = "secretpassword"
    hashed = security.hash_password(pwd)
    assert hashed != pwd
    assert security.verify_password(pwd, hashed) is True
    assert security.verify_password("wrongpassword", hashed) is False

def test_jwt_generation():
    token = security.create_access_token({"sub": "test@stocksense.com"})
    payload = security.decode_access_token(token)
    assert payload is not None
    assert payload.get("sub") == "test@stocksense.com"
