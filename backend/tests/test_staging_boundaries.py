import uuid

import pytest

from app.core.config import AppEnvironment, Settings
from app.services.storage import LocalCiphertextStorage


def remote_settings(**overrides):
    values = {
        "APP_ENV": "staging",
        "DEBUG": False,
        "PUBLIC_BASE_URL": "https://api.staging.example.com",
        "DATABASE_URL": "postgresql+psycopg2://woven:secret@db:5432/woven",
        "SECRET_KEY": "s" * 32,
        "REFRESH_TOKEN_PEPPER": "p" * 32,
        "APPLE_CLIENT_ID": "com.example.Woven",
        "TRUSTED_HOSTS": "api.staging.example.com",
        "STORAGE_BACKEND": "object",
        "OBJECT_STORAGE_ENDPOINT": "https://objects.example.com",
        "OBJECT_STORAGE_BUCKET": "ciphertext",
        "OBJECT_STORAGE_ACCESS_KEY": "access",
        "OBJECT_STORAGE_SECRET_KEY": "secret",
        "ENFORCE_DEVICE_SIGNATURES": True,
    }
    values.update(overrides)
    return Settings(**values)


def test_remote_configuration_fails_closed_for_http_sqlite_and_local_storage():
    with pytest.raises(ValueError, match="HTTPS"):
        remote_settings(PUBLIC_BASE_URL="http://api.staging.example.com")
    with pytest.raises(ValueError, match="PostgreSQL"):
        remote_settings(DATABASE_URL="sqlite:///staging.db")
    with pytest.raises(ValueError, match="STORAGE_BACKEND"):
        remote_settings(STORAGE_BACKEND="local")
    with pytest.raises(ValueError, match="ENFORCE_DEVICE_SIGNATURES"):
        remote_settings(ENFORCE_DEVICE_SIGNATURES=False)
    with pytest.raises(ValueError, match="independent"):
        remote_settings(SECRET_KEY="s" * 32, REFRESH_TOKEN_PEPPER="s" * 32)
    with pytest.raises(ValueError, match="TRUSTED_HOSTS cannot"):
        remote_settings(TRUSTED_HOSTS="*")
    with pytest.raises(ValueError, match="must include"):
        remote_settings(TRUSTED_HOSTS="different.example.com")
    with pytest.raises(ValueError, match="OBJECT_STORAGE_ENDPOINT"):
        remote_settings(OBJECT_STORAGE_ENDPOINT="http://objects.example.com")


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("APPLE_ISSUER", "https://apple.example.invalid"),
        ("APPLE_JWKS_URL", "https://apple.example.invalid/keys"),
    ],
)
def test_remote_apple_verification_endpoints_are_pinned(name, value):
    with pytest.raises(ValueError, match=name):
        remote_settings(**{name: value})


def test_development_password_endpoints_are_hidden_remotely(client):
    from app.core.config import settings

    previous = settings.APP_ENV
    settings.APP_ENV = AppEnvironment.PRODUCTION
    try:
        response = client.post(
            "/auth/signup",
            json={"username": "hidden", "email": "hidden@example.com", "password": "password123"},
        )
        assert response.status_code == 404
        malformed = client.post("/auth/apple", json={"identity_token": {"secret": "must-not-echo"}})
        assert malformed.status_code == 422
        assert malformed.json() == {"detail": "Invalid request"}
        assert "must-not-echo" not in malformed.text
    finally:
        settings.APP_ENV = previous


def test_health_is_minimal_and_responses_have_security_headers(client):
    response = client.get("/health")
    assert response.json() == {"status": "ok"}
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-frame-options"] == "DENY"
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-request-id"]


def test_authenticated_rate_limits_are_isolated_per_credential(client):
    from app.core.config import settings

    previous = settings.RATE_LIMIT_PAIR_PER_MINUTE
    settings.RATE_LIMIT_PAIR_PER_MINUTE = 1
    first = f"invalid-{uuid.uuid4()}"
    second = f"invalid-{uuid.uuid4()}"
    try:
        assert client.get(
            "/pair-v2/vaults", headers={"Authorization": f"Bearer {first}"}
        ).status_code == 401
        limited = client.get(
            "/pair-v2/vaults", headers={"Authorization": f"Bearer {first}"}
        )
        assert limited.status_code == 429
        assert limited.headers["cache-control"] == "no-store"
        assert limited.headers["x-content-type-options"] == "nosniff"
        assert client.get(
            "/pair-v2/vaults", headers={"Authorization": f"Bearer {second}"}
        ).status_code == 401
    finally:
        settings.RATE_LIMIT_PAIR_PER_MINUTE = previous


def test_local_ciphertext_storage_uses_opaque_keys_and_blocks_traversal(tmp_path):
    storage = LocalCiphertextStorage(str(tmp_path))
    key = storage.generate_storage_key("vault-id", "media-id", "private-name.jpg")
    assert key.startswith("objects/")
    assert "vault" not in key and "media" not in key and "private" not in key
    storage.save_file(key, b"ciphertext")
    assert storage.get_file(key) == b"ciphertext"
    with pytest.raises(ValueError):
        storage.get_file("../../outside")
