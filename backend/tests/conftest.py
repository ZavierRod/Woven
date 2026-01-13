"""
Test configuration and fixtures.

Uses a separate test database to avoid polluting production data.
"""
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
        "token": data["access_token"],
        "headers": {"Authorization": f"Bearer {data['access_token']}"}
    }


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
        "token": data["access_token"],
        "headers": {"Authorization": f"Bearer {data['access_token']}"}
    }

