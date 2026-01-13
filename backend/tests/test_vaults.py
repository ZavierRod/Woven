"""
Tests for vault endpoints.
"""
import pytest


class TestCreateVault:
    """Tests for POST /vaults/"""

    def test_create_solo_vault(self, client, test_user):
        """Test creating a solo vault."""
        response = client.post("/vaults/", 
            json={"name": "My Private Vault", "type": "solo", "mode": "normal"},
            headers=test_user["headers"]
        )
        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "My Private Vault"
        assert data["type"] == "solo"
        assert data["mode"] == "normal"
        assert data["owner_id"] == test_user["user_id"]
        assert data["member_count"] == 1  # Owner is a member

    def test_create_pair_vault(self, client, test_user):
        """Test creating a pair vault."""
        response = client.post("/vaults/",
            json={"name": "Shared Vault", "type": "pair", "mode": "normal"},
            headers=test_user["headers"]
        )
        assert response.status_code == 201
        assert response.json()["type"] == "pair"

    def test_create_strict_mode_vault(self, client, test_user):
        """Test creating a vault with strict mode."""
        response = client.post("/vaults/",
            json={"name": "Strict Vault", "type": "pair", "mode": "strict"},
            headers=test_user["headers"]
        )
        assert response.status_code == 201
        assert response.json()["mode"] == "strict"

    def test_create_vault_unauthenticated(self, client):
        """Test that unauthenticated vault creation is rejected."""
        response = client.post("/vaults/", json={"name": "Test Vault"})
        assert response.status_code == 401

    def test_create_vault_default_values(self, client, test_user):
        """Test that vault gets default type and mode."""
        response = client.post("/vaults/",
            json={"name": "Default Vault"},
            headers=test_user["headers"]
        )
        assert response.status_code == 201
        data = response.json()
        assert data["type"] == "solo"
        assert data["mode"] == "normal"

    def test_create_multiple_vaults_same_name(self, client, test_user):
        """Test that users can create multiple vaults with the same name."""
        response1 = client.post("/vaults/",
            json={"name": "Duplicate Name"},
            headers=test_user["headers"]
        )
        response2 = client.post("/vaults/",
            json={"name": "Duplicate Name"},
            headers=test_user["headers"]
        )
        assert response1.status_code == 201
        assert response2.status_code == 201
        # Different vault IDs
        assert response1.json()["id"] != response2.json()["id"]


class TestListVaults:
    """Tests for GET /vaults/"""

    def test_list_vaults_empty(self, client, test_user):
        """Test listing vaults when user has none."""
        response = client.get("/vaults/", headers=test_user["headers"])
        assert response.status_code == 200
        assert response.json() == []

    def test_list_own_vaults(self, client, test_user):
        """Test listing user's own vaults."""
        # Create some vaults
        client.post("/vaults/", json={"name": "Vault 1"}, headers=test_user["headers"])
        client.post("/vaults/", json={"name": "Vault 2"}, headers=test_user["headers"])
        
        response = client.get("/vaults/", headers=test_user["headers"])
        assert response.status_code == 200
        vaults = response.json()
        assert len(vaults) == 2

    def test_vaults_isolated_between_users(self, client, test_user, second_user):
        """Test that users only see their own vaults."""
        # User 1 creates a vault
        client.post("/vaults/", json={"name": "User1 Vault"}, headers=test_user["headers"])
        
        # User 2 creates a vault
        client.post("/vaults/", json={"name": "User2 Vault"}, headers=second_user["headers"])
        
        # User 1 should only see their vault
        response1 = client.get("/vaults/", headers=test_user["headers"])
        assert len(response1.json()) == 1
        assert response1.json()[0]["name"] == "User1 Vault"
        
        # User 2 should only see their vault
        response2 = client.get("/vaults/", headers=second_user["headers"])
        assert len(response2.json()) == 1
        assert response2.json()[0]["name"] == "User2 Vault"


class TestGetVault:
    """Tests for GET /vaults/{id}"""

    def test_get_vault_details(self, client, test_user):
        """Test getting vault details."""
        create_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        response = client.get(f"/vaults/{vault_id}", headers=test_user["headers"])
        assert response.status_code == 200
        data = response.json()
        assert data["name"] == "Test Vault"
        assert "members" in data
        assert len(data["members"]) == 1  # Owner

    def test_get_vault_not_found(self, client, test_user):
        """Test getting non-existent vault."""
        fake_id = "00000000-0000-0000-0000-000000000000"
        response = client.get(f"/vaults/{fake_id}", headers=test_user["headers"])
        assert response.status_code == 404

    def test_get_vault_forbidden(self, client, test_user, second_user):
        """Test that users can't access other users' vaults."""
        # User 1 creates a vault
        create_response = client.post("/vaults/",
            json={"name": "Private Vault"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        # User 2 tries to access it
        response = client.get(f"/vaults/{vault_id}", headers=second_user["headers"])
        assert response.status_code == 403


class TestUpdateVault:
    """Tests for PATCH /vaults/{id}"""

    def test_update_vault_name(self, client, test_user):
        """Test updating vault name."""
        create_response = client.post("/vaults/",
            json={"name": "Original Name"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        response = client.patch(f"/vaults/{vault_id}",
            json={"name": "New Name"},
            headers=test_user["headers"]
        )
        assert response.status_code == 200
        assert response.json()["name"] == "New Name"

    def test_update_vault_mode(self, client, test_user):
        """Test updating vault mode."""
        create_response = client.post("/vaults/",
            json={"name": "Test", "mode": "normal"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        response = client.patch(f"/vaults/{vault_id}",
            json={"mode": "strict"},
            headers=test_user["headers"]
        )
        assert response.status_code == 200
        assert response.json()["mode"] == "strict"

    def test_update_vault_forbidden(self, client, test_user, second_user):
        """Test that non-owners can't update vault."""
        create_response = client.post("/vaults/",
            json={"name": "Owner's Vault"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        response = client.patch(f"/vaults/{vault_id}",
            json={"name": "Hacked Name"},
            headers=second_user["headers"]
        )
        assert response.status_code == 403


class TestDeleteVault:
    """Tests for DELETE /vaults/{id}"""

    def test_delete_vault(self, client, test_user):
        """Test deleting a vault."""
        create_response = client.post("/vaults/",
            json={"name": "To Delete"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        # Delete it
        response = client.delete(f"/vaults/{vault_id}", headers=test_user["headers"])
        assert response.status_code == 204
        
        # Verify it's gone
        get_response = client.get(f"/vaults/{vault_id}", headers=test_user["headers"])
        assert get_response.status_code == 404

    def test_delete_vault_forbidden(self, client, test_user, second_user):
        """Test that non-owners can't delete vault."""
        create_response = client.post("/vaults/",
            json={"name": "Owner's Vault"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        response = client.delete(f"/vaults/{vault_id}", headers=second_user["headers"])
        assert response.status_code == 403

    def test_delete_vault_not_found(self, client, test_user):
        """Test deleting non-existent vault."""
        fake_id = "00000000-0000-0000-0000-000000000000"
        response = client.delete(f"/vaults/{fake_id}", headers=test_user["headers"])
        assert response.status_code == 404


class TestVaultInvitations:
    """Tests for vault invitation flow."""

    def test_invite_user_to_pair_vault(self, client, test_user, second_user):
        """Test inviting a user to a pair vault."""
        # Create a pair vault
        create_response = client.post("/vaults/",
            json={"name": "Shared Vault", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        # Get second user's invite code
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        # Invite second user
        response = client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        assert response.status_code == 200
        assert response.json()["status"] == "pending"

    def test_invite_to_solo_vault_fails(self, client, test_user, second_user):
        """Test that inviting to solo vault fails."""
        create_response = client.post("/vaults/",
            json={"name": "Solo Vault", "type": "solo"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        response = client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        assert response.status_code == 400

    def test_invite_self_fails(self, client, test_user):
        """Test that users can't invite themselves."""
        create_response = client.post("/vaults/",
            json={"name": "Pair Vault", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        user_response = client.get("/users/me", headers=test_user["headers"])
        invite_code = user_response.json()["invite_code"]
        
        response = client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        assert response.status_code == 400

    def test_accept_vault_invitation(self, client, test_user, second_user):
        """Test accepting a vault invitation."""
        # Create pair vault and invite
        create_response = client.post("/vaults/",
            json={"name": "Shared", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        
        # Second user accepts
        response = client.post(f"/vaults/{vault_id}/accept", headers=second_user["headers"])
        assert response.status_code == 200
        
        # Second user should now see the vault
        vaults_response = client.get("/vaults/", headers=second_user["headers"])
        vault_names = [v["name"] for v in vaults_response.json()]
        assert "Shared" in vault_names

    def test_decline_vault_invitation(self, client, test_user, second_user):
        """Test declining a vault invitation."""
        # Create pair vault and invite
        create_response = client.post("/vaults/",
            json={"name": "Declined", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        
        # Second user declines
        response = client.post(f"/vaults/{vault_id}/decline", headers=second_user["headers"])
        assert response.status_code == 204
        
        # Second user should NOT see the vault
        vaults_response = client.get("/vaults/", headers=second_user["headers"])
        assert len(vaults_response.json()) == 0

    def test_pair_vault_max_two_members(self, client, test_user, second_user):
        """Test that pair vaults can't have more than 2 members."""
        # Create pair vault and add second user
        create_response = client.post("/vaults/",
            json={"name": "Pair", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        client.post(f"/vaults/{vault_id}/accept", headers=second_user["headers"])
        
        # Create a third user
        third_user_data = {
            "username": "thirduser",
            "email": "third@example.com",
            "password": "thirdpassword123"
        }
        third_response = client.post("/auth/signup", json=third_user_data)
        third_headers = {"Authorization": f"Bearer {third_response.json()['access_token']}"}
        
        user3_response = client.get("/users/me", headers=third_headers)
        third_code = user3_response.json()["invite_code"]
        
        # Try to invite third user - should fail
        response = client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": third_code},
            headers=test_user["headers"]
        )
        assert response.status_code == 400
        assert "maximum" in response.json()["detail"].lower()


class TestLeaveVault:
    """Tests for DELETE /vaults/{id}/leave"""

    def test_member_can_leave_vault(self, client, test_user, second_user):
        """Test that a member can leave a vault."""
        # Create and invite
        create_response = client.post("/vaults/",
            json={"name": "Leave Test", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        client.post(f"/vaults/{vault_id}/accept", headers=second_user["headers"])
        
        # Second user leaves
        response = client.delete(f"/vaults/{vault_id}/leave", headers=second_user["headers"])
        assert response.status_code == 204
        
        # Verify they can't access it anymore
        get_response = client.get(f"/vaults/{vault_id}", headers=second_user["headers"])
        assert get_response.status_code == 403

    def test_owner_cannot_leave_vault(self, client, test_user):
        """Test that owner can't leave their own vault (must delete instead)."""
        create_response = client.post("/vaults/",
            json={"name": "Owner Vault"},
            headers=test_user["headers"]
        )
        vault_id = create_response.json()["id"]
        
        response = client.delete(f"/vaults/{vault_id}/leave", headers=test_user["headers"])
        assert response.status_code == 400

