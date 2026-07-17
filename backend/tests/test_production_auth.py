import hashlib
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.core.config import Settings
from app.core.security import AppleTokenError, AppleTokenVerifier
from app.main import app
from app.models.auth import RefreshCredential
from app.routers.auth import get_apple_verifier


def apple_token(private_key, nonce, audience="com.example.woven", subject="apple-subject-1", expires_in=300):
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            "sub": subject,
            "iss": "https://appleid.apple.com",
            "aud": audience,
            "iat": now,
            "exp": now + timedelta(seconds=expires_in),
            "nonce": hashlib.sha256(nonce.encode()).hexdigest(),
            "email": "private@example.com",
        },
        private_key,
        algorithm="RS256",
        headers={"kid": "test-key"},
    )


@pytest.fixture
def apple_verifier():
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    configuration = Settings(APPLE_CLIENT_ID="com.example.woven")
    verifier = AppleTokenVerifier(
        configuration=configuration,
        signing_key_resolver=lambda _token: private_key.public_key(),
    )
    return private_key, verifier


def test_apple_verifier_checks_signature_audience_expiry_and_nonce(apple_verifier):
    private_key, verifier = apple_verifier
    token = apple_token(private_key, "raw-nonce")
    assert verifier.verify(token, "raw-nonce")["sub"] == "apple-subject-1"

    with pytest.raises(AppleTokenError):
        verifier.verify(token, "different-nonce")
    with pytest.raises(AppleTokenError):
        verifier.verify(apple_token(private_key, "raw-nonce", audience="wrong-client"), "raw-nonce")
    with pytest.raises(AppleTokenError):
        verifier.verify(apple_token(private_key, "raw-nonce", expires_in=-1), "raw-nonce")


def test_apple_session_rotates_refresh_and_reuse_revokes_family(client, db, apple_verifier):
    private_key, verifier = apple_verifier
    app.dependency_overrides[get_apple_verifier] = lambda: verifier
    try:
        signed_in = client.post(
            "/auth/apple",
            json={
                "identity_token": apple_token(private_key, "raw-nonce"),
                "nonce": "raw-nonce",
                "full_name": "Private User",
            },
        )
        assert signed_in.status_code == 200, signed_in.text
        first = signed_in.json()
        assert first["refresh_token"] not in {
            record.token_hash for record in db.query(RefreshCredential).all()
        }

        rotated = client.post("/auth/refresh", json={"refresh_token": first["refresh_token"]})
        assert rotated.status_code == 200, rotated.text
        second = rotated.json()
        assert second["refresh_token"] != first["refresh_token"]

        reused = client.post("/auth/refresh", json={"refresh_token": first["refresh_token"]})
        assert reused.status_code == 401
        stale_access = client.get(
            "/users/me",
            headers={"Authorization": f"Bearer {second['access_token']}"},
        )
        assert stale_access.status_code == 401
    finally:
        app.dependency_overrides.pop(get_apple_verifier, None)
