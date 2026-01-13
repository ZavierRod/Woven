"""
Tests for media endpoints.
"""
import pytest
import io
from uuid import uuid4


class TestUploadMedia:
    """Tests for POST /media/"""

    def test_upload_media_success(self, client, test_user):
        """Test successful media upload."""
        # Create a vault first
        vault_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        # Prepare file upload
        file_content = b"fake encrypted file content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        
        response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        
        assert response.status_code == 201
        data = response.json()
        assert data["file_name"] == "test.jpg"
        assert data["media_type"] == "photo"
        assert data["vault_id"] == str(vault_id)
        assert data["uploaded_by_id"] == test_user["user_id"]

    def test_upload_media_wrong_file_size(self, client, test_user):
        """Test upload with incorrect file size."""
        vault_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        file_content = b"small file"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": "999999",  # Wrong size
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        
        response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        
        assert response.status_code == 400
        assert "size mismatch" in response.json()["detail"].lower()

    def test_upload_media_no_access(self, client, test_user, second_user):
        """Test upload to vault user doesn't have access to."""
        # User 1 creates vault
        vault_response = client.post("/vaults/",
            json={"name": "Private Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        # User 2 tries to upload
        file_content = b"encrypted content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        
        response = client.post("/media/",
            files=files,
            data=data,
            headers=second_user["headers"]
        )
        
        assert response.status_code == 403

    def test_upload_media_invalid_type(self, client, test_user):
        """Test upload with invalid media type."""
        vault_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        file_content = b"content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "invalid",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        
        response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        
        assert response.status_code == 400

    def test_upload_video(self, client, test_user):
        """Test uploading a video."""
        vault_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        file_content = b"fake encrypted video content"
        files = {"file": ("test.mp4", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.mp4",
            "file_size": str(len(file_content)),
            "media_type": "video",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        
        response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        
        assert response.status_code == 201
        assert response.json()["media_type"] == "video"


class TestListVaultMedia:
    """Tests for GET /media/vault/{vault_id}"""

    def test_list_media_empty(self, client, test_user):
        """Test listing media in empty vault."""
        vault_response = client.post("/vaults/",
            json={"name": "Empty Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        response = client.get(f"/media/vault/{vault_id}", headers=test_user["headers"])
        
        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 0
        assert data["media"] == []

    def test_list_media_with_items(self, client, test_user):
        """Test listing media in vault with items."""
        vault_response = client.post("/vaults/",
            json={"name": "Media Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        # Upload two files
        file1_content = b"file 1"
        files1 = {"file": ("photo1.jpg", io.BytesIO(file1_content), "application/octet-stream")}
        data1 = {
            "vault_id": str(vault_id),
            "file_name": "photo1.jpg",
            "file_size": str(len(file1_content)),
            "media_type": "photo",
            "encryption_iv": "iv1",
            "encryption_tag": "tag1",
        }
        client.post("/media/", files=files1, data=data1, headers=test_user["headers"])
        
        file2_content = b"file 2"
        files2 = {"file": ("photo2.jpg", io.BytesIO(file2_content), "application/octet-stream")}
        data2 = {
            "vault_id": str(vault_id),
            "file_name": "photo2.jpg",
            "file_size": str(len(file2_content)),
            "media_type": "photo",
            "encryption_iv": "iv2",
            "encryption_tag": "tag2",
        }
        client.post("/media/", files=files2, data=data2, headers=test_user["headers"])
        
        # List media
        response = client.get(f"/media/vault/{vault_id}", headers=test_user["headers"])
        
        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 2
        assert len(data["media"]) == 2

    def test_list_media_no_access(self, client, test_user, second_user):
        """Test listing media in vault user doesn't have access to."""
        vault_response = client.post("/vaults/",
            json={"name": "Private Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        response = client.get(f"/media/vault/{vault_id}", headers=second_user["headers"])
        
        assert response.status_code == 403


class TestViewMedia:
    """Tests for GET /media/{media_id}/view"""

    def test_view_media(self, client, test_user):
        """Test viewing media file."""
        # Create vault and upload
        vault_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        file_content = b"encrypted file content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        upload_response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        media_id = upload_response.json()["id"]
        
        # View media
        response = client.get(f"/media/{media_id}/view", headers=test_user["headers"])
        
        assert response.status_code == 200
        assert response.headers["content-type"] == "application/octet-stream"
        assert len(response.content) == len(file_content)

    def test_view_media_no_access(self, client, test_user, second_user):
        """Test viewing media user doesn't have access to."""
        vault_response = client.post("/vaults/",
            json={"name": "Private Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        file_content = b"encrypted content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        upload_response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        media_id = upload_response.json()["id"]
        
        # User 2 tries to view
        response = client.get(f"/media/{media_id}/view", headers=second_user["headers"])
        
        assert response.status_code == 403

    def test_view_media_not_found(self, client, test_user):
        """Test viewing non-existent media."""
        fake_id = uuid4()
        response = client.get(f"/media/{fake_id}/view", headers=test_user["headers"])
        
        assert response.status_code == 404


class TestDeleteMedia:
    """Tests for DELETE /media/{media_id}"""

    def test_delete_media_owner(self, client, test_user):
        """Test vault owner deleting media."""
        vault_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        file_content = b"encrypted content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        upload_response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        media_id = upload_response.json()["id"]
        
        # Delete media
        response = client.delete(f"/media/{media_id}", headers=test_user["headers"])
        
        assert response.status_code == 204
        
        # Verify it's gone
        view_response = client.get(f"/media/{media_id}/view", headers=test_user["headers"])
        assert view_response.status_code == 404

    def test_delete_media_uploader(self, client, test_user, second_user):
        """Test media uploader (non-owner) deleting their own media."""
        # Create pair vault and add second user
        vault_response = client.post("/vaults/",
            json={"name": "Shared Vault", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        client.post(f"/vaults/{vault_id}/accept", headers=second_user["headers"])
        
        # User 2 uploads media
        file_content = b"encrypted content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        upload_response = client.post("/media/",
            files=files,
            data=data,
            headers=second_user["headers"]
        )
        media_id = upload_response.json()["id"]
        
        # User 2 can delete their own media
        response = client.delete(f"/media/{media_id}", headers=second_user["headers"])
        
        assert response.status_code == 204

    def test_delete_media_no_permission(self, client, test_user, second_user):
        """Test that other users can't delete media they didn't upload."""
        vault_response = client.post("/vaults/",
            json={"name": "Shared Vault", "type": "pair"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        user2_response = client.get("/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]
        
        client.post(f"/vaults/{vault_id}/invite",
            json={"invite_code": invite_code},
            headers=test_user["headers"]
        )
        client.post(f"/vaults/{vault_id}/accept", headers=second_user["headers"])
        
        # User 1 uploads media
        file_content = b"encrypted content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        upload_response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        media_id = upload_response.json()["id"]
        
        # User 2 (member, not owner) tries to delete User 1's media
        response = client.delete(f"/media/{media_id}", headers=second_user["headers"])
        
        assert response.status_code == 403

    def test_delete_media_not_found(self, client, test_user):
        """Test deleting non-existent media."""
        fake_id = uuid4()
        response = client.delete(f"/media/{fake_id}", headers=test_user["headers"])
        
        assert response.status_code == 404


class TestGetViewUrl:
    """Tests for GET /media/{media_id}/view-url"""

    def test_get_view_url(self, client, test_user):
        """Test getting view URL for media."""
        vault_response = client.post("/vaults/",
            json={"name": "Test Vault"},
            headers=test_user["headers"]
        )
        vault_id = vault_response.json()["id"]
        
        file_content = b"encrypted content"
        files = {"file": ("test.jpg", io.BytesIO(file_content), "application/octet-stream")}
        data = {
            "vault_id": str(vault_id),
            "file_name": "test.jpg",
            "file_size": str(len(file_content)),
            "media_type": "photo",
            "encryption_iv": "base64iv123",
            "encryption_tag": "base64tag123",
        }
        upload_response = client.post("/media/",
            files=files,
            data=data,
            headers=test_user["headers"]
        )
        media_id = upload_response.json()["id"]
        
        response = client.get(f"/media/{media_id}/view-url", headers=test_user["headers"])
        
        assert response.status_code == 200
        data = response.json()
        assert "view_url" in data
        assert "expires_in" in data
        assert data["expires_in"] > 0


