"""
Tests for user endpoints.
"""
import pytest


class TestGetCurrentUser:
    """Tests for GET /users/me"""

    def test_get_current_user_authenticated(self, client, test_user):
        """Test getting current user profile."""
        response = client.get("/users/me", headers=test_user["headers"])
        assert response.status_code == 200
        data = response.json()
        assert data["username"] == test_user["username"]
        assert data["email"] == test_user["email"]
        assert "invite_code" in data

    def test_get_current_user_unauthenticated(self, client):
        """Test that unauthenticated requests are rejected."""
        response = client.get("/users/me")
        assert response.status_code == 401

    def test_get_current_user_invalid_token(self, client):
        """Test with invalid token."""
        response = client.get("/users/me", headers={"Authorization": "Bearer invalidtoken"})
        assert response.status_code == 401


class TestGetUserByInviteCode:
    """Tests for GET /users/{invite_code}"""

    def test_find_user_by_invite_code(self, client, test_user):
        """Test finding a user by their invite code."""
        # First get the user's invite code
        me_response = client.get("/users/me", headers=test_user["headers"])
        invite_code = me_response.json()["invite_code"]
        
        # Now look them up by invite code
        response = client.get(f"/users/{invite_code}", headers=test_user["headers"])
        assert response.status_code == 200
        assert response.json()["username"] == test_user["username"]

    def test_find_user_invalid_invite_code(self, client, test_user):
        """Test with non-existent invite code."""
        response = client.get("/users/INVALID123", headers=test_user["headers"])
        assert response.status_code == 404

    def test_find_user_unauthenticated(self, client, test_user):
        """Test that invite code lookup requires authentication."""
        me_response = client.get("/users/me", headers=test_user["headers"])
        invite_code = me_response.json()["invite_code"]
        
        response = client.get(f"/users/{invite_code}")
        assert response.status_code == 401


class TestUniqueInviteCodes:
    """Tests for invite code uniqueness."""

    def test_users_have_unique_invite_codes(self, client, test_user, second_user):
        """Test that each user gets a unique invite code."""
        user1_response = client.get("/users/me", headers=test_user["headers"])
        user2_response = client.get("/users/me", headers=second_user["headers"])
        
        code1 = user1_response.json()["invite_code"]
        code2 = user2_response.json()["invite_code"]
        
        assert code1 != code2
        assert code1 is not None
        assert code2 is not None

