import hashlib
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.core.config import Settings
from app.core.security import (
    AppleTokenError,
    AppleTokenVerifier,
    GoogleTokenError,
    GoogleTokenVerifier,
)
from app.main import app
from app.models.auth import RefreshCredential
from app.models.user import User
from app.routers.auth import get_apple_verifier, get_google_verifier


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


def google_token(
    private_key,
    audience="woven-server-client",
    subject="google-subject-1",
    expires_in=300,
    issuer="https://accounts.google.com",
    email_verified=True,
    authorized_party=None,
):
    now = datetime.now(timezone.utc)
    claims = {
        "sub": subject,
        "iss": issuer,
        "aud": audience,
        "iat": now,
        "exp": now + timedelta(seconds=expires_in),
        "email": "private@example.com",
        "email_verified": email_verified,
        "name": "Google Test User",
    }
    if authorized_party is not None:
        claims["azp"] = authorized_party
    return jwt.encode(
        claims,
        private_key,
        algorithm="RS256",
        headers={"kid": "google-test-key"},
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


@pytest.fixture
def google_verifier():
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    configuration = Settings(GOOGLE_CLIENT_ID="woven-server-client")
    verifier = GoogleTokenVerifier(
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


def test_google_verifier_checks_signature_audience_issuer_expiry_and_verified_email(google_verifier):
    private_key, verifier = google_verifier
    token = google_token(private_key)
    assert verifier.verify(token)["sub"] == "google-subject-1"

    with pytest.raises(GoogleTokenError):
        verifier.verify(google_token(private_key, audience="wrong-client"))
    with pytest.raises(GoogleTokenError):
        verifier.verify(google_token(private_key, issuer="https://accounts.example.invalid"))
    with pytest.raises(GoogleTokenError):
        verifier.verify(google_token(private_key, expires_in=-1))
    with pytest.raises(GoogleTokenError):
        verifier.verify(google_token(private_key, email_verified=False))
    # With the iOS-to-backend flow, azp can name the iOS OAuth client while
    # aud names the backend client. The verifier must bind aud, not conflate
    # these two client identifiers.
    mobile_token = google_token(private_key, authorized_party="woven-ios-client")
    assert verifier.verify(mobile_token)["azp"] == "woven-ios-client"


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


def test_google_session_is_distinct_from_apple_even_when_verified_email_matches(
    client,
    db,
    apple_verifier,
    google_verifier,
):
    apple_private_key, apple = apple_verifier
    google_private_key, google = google_verifier
    app.dependency_overrides[get_apple_verifier] = lambda: apple
    app.dependency_overrides[get_google_verifier] = lambda: google
    try:
        apple_response = client.post(
            "/auth/apple",
            json={
                "identity_token": apple_token(apple_private_key, "raw-nonce"),
                "nonce": "raw-nonce",
                "full_name": "Apple Test User",
            },
        )
        google_response = client.post(
            "/auth/google",
            json={"id_token": google_token(google_private_key)},
        )

        assert apple_response.status_code == 200, apple_response.text
        assert google_response.status_code == 200, google_response.text
        assert apple_response.json()["user_id"] != google_response.json()["user_id"]
        google_user = db.query(User).filter(User.google_user_id == "google-subject-1").one()
        assert google_user.apple_user_id is None
        assert google_user.email.endswith("@identity.invalid")
        assert google_response.json()["refresh_token"] not in {
            record.token_hash for record in db.query(RefreshCredential).all()
        }
    finally:
        app.dependency_overrides.pop(get_apple_verifier, None)
        app.dependency_overrides.pop(get_google_verifier, None)


def test_apple_session_remains_distinct_when_google_account_exists_first(
    client,
    db,
    apple_verifier,
    google_verifier,
):
    apple_private_key, apple = apple_verifier
    google_private_key, google = google_verifier
    app.dependency_overrides[get_apple_verifier] = lambda: apple
    app.dependency_overrides[get_google_verifier] = lambda: google
    try:
        google_response = client.post(
            "/auth/google",
            json={"id_token": google_token(google_private_key)},
        )
        apple_response = client.post(
            "/auth/apple",
            json={
                "identity_token": apple_token(apple_private_key, "raw-nonce"),
                "nonce": "raw-nonce",
            },
        )

        assert google_response.status_code == 200, google_response.text
        assert apple_response.status_code == 200, apple_response.text
        assert google_response.json()["user_id"] != apple_response.json()["user_id"]
        apple_user = db.query(User).filter(User.apple_user_id == "apple-subject-1").one()
        assert apple_user.google_user_id is None
        assert apple_user.email.endswith("@identity.invalid")
    finally:
        app.dependency_overrides.pop(get_apple_verifier, None)
        app.dependency_overrides.pop(get_google_verifier, None)
