"""
Tests for friends endpoints.
"""
import pytest


class TestSendFriendRequest:
    """Tests for POST /friends/request"""

    def test_send_friend_request(self, client, test_user, second_user):
        """Test sending a friend request with valid invite code."""
        # Get second user's invite code
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        # Send friend request
        response = client.post("/friends/request",
                               json={"invite_code": invite_code},
                               headers=test_user["headers"]
                               )
        assert response.status_code == 201
        data = response.json()
        assert data["user_id"] == test_user["user_id"]
        assert data["friend_id"] == second_user["user_id"]
        assert data["status"] == "pending"

    def test_send_request_invalid_invite_code(self, client, test_user):
        """Test sending request with non-existent invite code."""
        response = client.post("/friends/request",
                               json={"invite_code": "INVALID123"},
                               headers=test_user["headers"]
                               )
        assert response.status_code == 404
        assert "not found" in response.json()["detail"].lower()

    def test_send_request_to_self(self, client, test_user):
        """Test that users can't send friend request to themselves."""
        # Get own invite code
        user_response = client.get("/users/me", headers=test_user["headers"])
        invite_code = user_response.json()["invite_code"]

        response = client.post("/friends/request",
                               json={"invite_code": invite_code},
                               headers=test_user["headers"]
                               )
        assert response.status_code == 400
        assert "yourself" in response.json()["detail"].lower()

    def test_send_duplicate_request(self, client, test_user, second_user):
        """Test that duplicate friend requests fail."""
        # Get second user's invite code
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        # First request should succeed
        response1 = client.post("/friends/request",
                                json={"invite_code": invite_code},
                                headers=test_user["headers"]
                                )
        assert response1.status_code == 201

        # Second request should fail
        response2 = client.post("/friends/request",
                                json={"invite_code": invite_code},
                                headers=test_user["headers"]
                                )
        assert response2.status_code == 400
        assert "already exists" in response2.json()["detail"].lower()

    def test_send_request_unauthenticated(self, client):
        """Test that unauthenticated requests are rejected."""
        response = client.post("/friends/request",
                               json={"invite_code": "ABC123"}
                               )
        assert response.status_code == 401


class TestAcceptFriendRequest:
    """Tests for POST /friends/requests/{id}/accept"""

    def test_accept_friend_request(self, client, test_user, second_user):
        """Test accepting a friend request."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        # Second user accepts
        response = client.post(f"/friends/requests/{friendship_id}/accept",
                               headers=second_user["headers"]
                               )
        assert response.status_code == 200
        assert response.json()["status"] == "accepted"

    def test_accept_request_wrong_user(self, client, test_user, second_user):
        """Test that only the recipient can accept."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        # First user (sender) tries to accept - should fail
        response = client.post(f"/friends/requests/{friendship_id}/accept",
                               headers=test_user["headers"]
                               )
        assert response.status_code == 404

    def test_accept_nonexistent_request(self, client, test_user):
        """Test accepting a non-existent request."""
        response = client.post("/friends/requests/99999/accept",
                               headers=test_user["headers"]
                               )
        assert response.status_code == 404


class TestDeclineFriendRequest:
    """Tests for POST /friends/requests/{id}/decline"""

    def test_decline_friend_request(self, client, test_user, second_user):
        """Test declining a friend request."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        # Second user declines
        response = client.post(f"/friends/requests/{friendship_id}/decline",
                               headers=second_user["headers"]
                               )
        assert response.status_code == 204

    def test_decline_request_wrong_user(self, client, test_user, second_user):
        """Test that only the recipient can decline."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        # First user (sender) tries to decline - should fail
        response = client.post(f"/friends/requests/{friendship_id}/decline",
                               headers=test_user["headers"]
                               )
        assert response.status_code == 404


class TestGetFriends:
    """Tests for GET /friends/"""

    def test_get_friends_empty(self, client, test_user):
        """Test getting friends list when user has none."""
        response = client.get("/friends/", headers=test_user["headers"])
        assert response.status_code == 200
        data = response.json()
        assert data["friends"] == []
        assert data["total"] == 0

    def test_get_friends_after_accept(self, client, test_user, second_user):
        """Test that friends appear after accepting request."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        # Second user accepts
        client.post(f"/friends/requests/{friendship_id}/accept",
                    headers=second_user["headers"]
                    )

        # Both users should now see each other as friends
        response1 = client.get("/friends/", headers=test_user["headers"])
        assert response1.status_code == 200
        assert response1.json()["total"] == 1
        assert response1.json()["friends"][0]["username"] == "seconduser"

        response2 = client.get("/friends/", headers=second_user["headers"])
        assert response2.status_code == 200
        assert response2.json()["total"] == 1
        assert response2.json()["friends"][0]["username"] == "testuser"

    def test_pending_requests_not_in_friends(self, client, test_user, second_user):
        """Test that pending requests don't appear in friends list."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        client.post("/friends/request",
                    json={"invite_code": invite_code},
                    headers=test_user["headers"]
                    )

        # Friends list should still be empty (request not accepted)
        response = client.get("/friends/", headers=test_user["headers"])
        assert response.status_code == 200
        assert response.json()["total"] == 0


class TestGetPendingRequests:
    """Tests for GET /friends/requests/pending"""

    def test_get_pending_requests(self, client, test_user, second_user):
        """Test getting incoming pending requests."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        client.post("/friends/request",
                    json={"invite_code": invite_code},
                    headers=test_user["headers"]
                    )

        # Second user should see the pending request
        response = client.get("/friends/requests/pending",
                              headers=second_user["headers"]
                              )
        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 1
        assert data["requests"][0]["requester"]["username"] == "testuser"

    def test_sender_has_no_pending_requests(self, client, test_user, second_user):
        """Test that sender doesn't see their own request as pending."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        client.post("/friends/request",
                    json={"invite_code": invite_code},
                    headers=test_user["headers"]
                    )

        # First user (sender) should not see pending requests
        response = client.get("/friends/requests/pending",
                              headers=test_user["headers"]
                              )
        assert response.status_code == 200
        assert response.json()["total"] == 0


class TestGetSentRequests:
    """Tests for GET /friends/requests/sent"""

    def test_get_sent_requests(self, client, test_user, second_user):
        """Test getting outgoing sent requests."""
        # Get second user's invite code and send request
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        client.post("/friends/request",
                    json={"invite_code": invite_code},
                    headers=test_user["headers"]
                    )

        # First user should see their sent request
        response = client.get("/friends/requests/sent",
                              headers=test_user["headers"]
                              )
        assert response.status_code == 200
        data = response.json()
        assert data["total"] == 1


class TestRemoveFriend:
    """Tests for DELETE /friends/{friend_user_id}"""

    def test_remove_friend(self, client, test_user, second_user):
        """Test removing an existing friend."""
        # Create friendship
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        client.post(f"/friends/requests/{friendship_id}/accept",
                    headers=second_user["headers"]
                    )

        # Remove friend
        response = client.delete(f"/friends/{second_user['user_id']}",
                                 headers=test_user["headers"]
                                 )
        assert response.status_code == 204

        # Verify they're no longer friends
        friends_response = client.get(
            "/friends/", headers=test_user["headers"])
        assert friends_response.json()["total"] == 0

    def test_remove_nonexistent_friend(self, client, test_user):
        """Test removing someone who isn't a friend."""
        response = client.delete("/friends/99999",
                                 headers=test_user["headers"]
                                 )
        assert response.status_code == 404

    def test_either_user_can_remove(self, client, test_user, second_user):
        """Test that either user can remove the friendship."""
        # Create friendship
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        client.post(f"/friends/requests/{friendship_id}/accept",
                    headers=second_user["headers"]
                    )

        # Second user removes (they were the recipient of the original request)
        response = client.delete(f"/friends/{test_user['user_id']}",
                                 headers=second_user["headers"]
                                 )
        assert response.status_code == 204


class TestRequestAfterDecline:
    """Tests for re-sending requests after decline."""

    def test_can_send_request_after_decline(self, client, test_user, second_user):
        """Test that a new request can be sent after declining."""
        # Get second user's invite code
        user2_response = client.get(
            "/users/me", headers=second_user["headers"])
        invite_code = user2_response.json()["invite_code"]

        # Send and decline
        send_response = client.post("/friends/request",
                                    json={"invite_code": invite_code},
                                    headers=test_user["headers"]
                                    )
        friendship_id = send_response.json()["id"]

        client.post(f"/friends/requests/{friendship_id}/decline",
                    headers=second_user["headers"]
                    )

        # Should be able to send again
        response = client.post("/friends/request",
                               json={"invite_code": invite_code},
                               headers=test_user["headers"]
                               )
        assert response.status_code == 201
