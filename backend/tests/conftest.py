"""
Test configuration and fixtures.

Uses a separate test database to avoid polluting production data.
"""
import os

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("DEBUG", "false")
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("PUBLIC_BASE_URL", "http://testserver")
os.environ.setdefault("SECRET_KEY", "woven-backend-automated-tests-only-key")
os.environ.setdefault("REFRESH_TOKEN_PEPPER", "woven-backend-refresh-tests-only-key")
os.environ.setdefault("RATE_LIMIT_AUTH_PER_MINUTE", "10000")
os.environ.setdefault("RATE_LIMIT_PAIR_PER_MINUTE", "10000")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.db.session import Base
from app.deps import get_db


# Use in-memory SQLite for fast tests
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def override_get_db():
    """Override database dependency with test database."""
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()


@pytest.fixture(scope="function")
def db():
    """Create a fresh database for each test."""
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture(scope="function")
def client(db):
    """Create a test client with database override."""
    app.dependency_overrides[get_db] = override_get_db
    Base.metadata.create_all(bind=engine)
    
    with TestClient(app) as c:
        yield c
    
    Base.metadata.drop_all(bind=engine)
    app.dependency_overrides.clear()


@pytest.fixture
def test_user(client):
    """Create a test user and return credentials + token."""
    user_data = {
        "username": "testuser",
        "email": "test@example.com",
        "password": "testpassword123",
        "full_name": "Test User"
    }
    response = client.post("/auth/signup", json=user_data)
    assert response.status_code == 201
    data = response.json()
    return {
        **user_data,
        "user_id": data["user_id"],
        "invite_code": data["invite_code"],
        "token": data["access_token"],
        "headers": {"Authorization": f"Bearer {data['access_token']}"}
    }


@pytest.fixture
def test_user_token(test_user):
    """Compatibility fixture for endpoint tests that only need the JWT."""
    return test_user["token"]


@pytest.fixture
def second_user(client):
    """Create a second test user for multi-user tests."""
    user_data = {
        "username": "seconduser",
        "email": "second@example.com",
        "password": "secondpassword123",
        "full_name": "Second User"
    }
    response = client.post("/auth/signup", json=user_data)
    assert response.status_code == 201
    data = response.json()
    return {
        **user_data,
        "user_id": data["user_id"],
        "invite_code": data["invite_code"],
        "token": data["access_token"],
        "headers": {"Authorization": f"Bearer {data['access_token']}"}
    }


@pytest.fixture
def friends(client, test_user, second_user):
    """Create and accept the legacy friendship required by legacy Pair APIs."""
    request = client.post(
        "/friends/request",
        json={"invite_code": second_user["invite_code"]},
        headers=test_user["headers"],
    )
    assert request.status_code == 201
    accepted = client.post(
        f"/friends/requests/{request.json()['id']}/accept",
        headers=second_user["headers"],
    )
    assert accepted.status_code == 200
    return test_user, second_user
