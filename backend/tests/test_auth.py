"""
Tests for authentication endpoints.
"""
import pytest


class TestSignUp:
    """Tests for POST /auth/signup"""

    def test_signup_success(self, client):
        """Test successful user registration."""
        response = client.post("/auth/signup", json={
            "username": "newuser",
            "email": "newuser@example.com",
            "password": "securepassword123",
            "full_name": "New User"
        })
        assert response.status_code == 201
        data = response.json()
        assert "access_token" in data
        assert data["username"] == "newuser"
        assert data["email"] == "newuser@example.com"
        assert data["full_name"] == "New User"

    def test_signup_duplicate_email(self, client, test_user):
        """Test that duplicate emails are rejected."""
        response = client.post("/auth/signup", json={
            "username": "differentuser",
            "email": test_user["email"],  # Same email as test_user
            "password": "anotherpassword123"
        })
        assert response.status_code == 400
        assert "Email already registered" in response.json()["detail"]

    def test_signup_duplicate_email_case_insensitive(self, client, test_user):
        """Test that email uniqueness is case-insensitive."""
        response = client.post("/auth/signup", json={
            "username": "differentuser",
            "email": test_user["email"].upper(),  # Same email, different case
            "password": "anotherpassword123"
        })
        assert response.status_code == 400
        assert "Email already registered" in response.json()["detail"]

    def test_signup_duplicate_username(self, client, test_user):
        """Test that duplicate usernames are rejected."""
        response = client.post("/auth/signup", json={
            "username": test_user["username"],  # Same username
            "email": "different@example.com",
            "password": "anotherpassword123"
        })
        assert response.status_code == 400
        assert "Username already taken" in response.json()["detail"]

    def test_signup_duplicate_username_case_insensitive(self, client, test_user):
        """Test that username uniqueness is case-insensitive."""
        response = client.post("/auth/signup", json={
            "username": test_user["username"].upper(),  # Same username, different case
            "email": "different@example.com",
            "password": "anotherpassword123"
        })
        assert response.status_code == 400
        assert "Username already taken" in response.json()["detail"]

    def test_signup_username_too_short(self, client):
        """Test that username must be at least 3 characters."""
        response = client.post("/auth/signup", json={
            "username": "ab",
            "email": "test@example.com",
            "password": "validpassword123"
        })
        assert response.status_code == 422  # Validation error

    def test_signup_username_too_long(self, client):
        """Test that username must be less than 30 characters."""
        response = client.post("/auth/signup", json={
            "username": "a" * 31,
            "email": "test@example.com",
            "password": "validpassword123"
        })
        assert response.status_code == 422

    def test_signup_username_invalid_characters(self, client):
        """Test that username only allows alphanumeric and underscore."""
        invalid_usernames = ["user@name", "user-name", "user.name", "user name", "user!"]
        for username in invalid_usernames:
            response = client.post("/auth/signup", json={
                "username": username,
                "email": f"{username.replace(' ', '').replace('@', '').replace('!', '')}@example.com",
                "password": "validpassword123"
            })
            assert response.status_code == 422, f"Username '{username}' should be rejected"

    def test_signup_password_too_short(self, client):
        """Test that password must be at least 8 characters."""
        response = client.post("/auth/signup", json={
            "username": "validuser",
            "email": "test@example.com",
            "password": "short"
        })
        assert response.status_code == 422

    def test_signup_invalid_email(self, client):
        """Test that invalid emails are rejected."""
        invalid_emails = ["notanemail", "missing@domain", "@nodomain.com"]
        for email in invalid_emails:
            response = client.post("/auth/signup", json={
                "username": "validuser",
                "email": email,
                "password": "validpassword123"
            })
            assert response.status_code == 422, f"Email '{email}' should be rejected"

    def test_signup_username_normalized_to_lowercase(self, client):
        """Test that username is normalized to lowercase."""
        response = client.post("/auth/signup", json={
            "username": "TestUser",
            "email": "test@example.com",
            "password": "validpassword123"
        })
        assert response.status_code == 201
        assert response.json()["username"] == "testuser"


class TestLogin:
    """Tests for POST /auth/login"""

    def test_login_with_email(self, client, test_user):
        """Test login with email."""
        response = client.post("/auth/login", json={
            "identifier": test_user["email"],
            "password": test_user["password"]
        })
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert data["username"] == test_user["username"]

    def test_login_with_username(self, client, test_user):
        """Test login with username."""
        response = client.post("/auth/login", json={
            "identifier": test_user["username"],
            "password": test_user["password"]
        })
        assert response.status_code == 200
        assert "access_token" in response.json()

    def test_login_case_insensitive_email(self, client, test_user):
        """Test that email login is case-insensitive."""
        response = client.post("/auth/login", json={
            "identifier": test_user["email"].upper(),
            "password": test_user["password"]
        })
        assert response.status_code == 200

    def test_login_case_insensitive_username(self, client, test_user):
        """Test that username login is case-insensitive."""
        response = client.post("/auth/login", json={
            "identifier": test_user["username"].upper(),
            "password": test_user["password"]
        })
        assert response.status_code == 200

    def test_login_wrong_password(self, client, test_user):
        """Test login with wrong password."""
        response = client.post("/auth/login", json={
            "identifier": test_user["email"],
            "password": "wrongpassword"
        })
        assert response.status_code == 401
        assert "Invalid" in response.json()["detail"]

    def test_login_nonexistent_user(self, client):
        """Test login with non-existent user."""
        response = client.post("/auth/login", json={
            "identifier": "nobody@example.com",
            "password": "anypassword"
        })
        assert response.status_code == 401

    def test_login_empty_password(self, client, test_user):
        """Test login with empty password."""
        response = client.post("/auth/login", json={
            "identifier": test_user["email"],
            "password": ""
        })
        assert response.status_code == 401

