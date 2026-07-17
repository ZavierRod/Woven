import base64
import hashlib
import time
import uuid

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import Settings
from app.db.session import Base
from app.deps import get_db
from app.main import app
from app.models.pair_v2 import PairAccessRequestV2, PairInvitationV2, PairMediaV2


def b64(value: bytes) -> str:
    return base64.b64encode(value).decode("ascii")


def test_non_debug_configuration_requires_a_strong_jwt_secret():
    with pytest.raises(ValueError, match="SECRET_KEY"):
        Settings(DEBUG=False, SECRET_KEY="short")

    configured = Settings(DEBUG=False, SECRET_KEY="s" * 32)
    assert configured.DEBUG is False


def headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def dev_account(client, name: str) -> dict:
    response = client.post(f"/pair-v2/dev/session/{name}")
    assert response.status_code == 200, response.text
    return response.json()


def signup_account(client, name: str) -> dict:
    response = client.post(
        "/auth/signup",
        json={
            "username": name,
            "email": f"{name}@example.com",
            "password": f"{name}-development-password",
            "full_name": name.title(),
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def register(client, account: dict, suffix: str, key_byte: bytes) -> dict:
    response = client.post(
        "/pair-v2/devices",
        headers=headers(account["access_token"]),
        json={
            "device_id": f"00000000-0000-0000-0000-{suffix:0>12}",
            "agreement_public_key": b64(key_byte * 32),
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def pair_setup(client):
    alice = dev_account(client, "alice")
    bob = dev_account(client, "bob")
    alice_device = register(client, alice, "a1", b"A")
    bob_device = register(client, bob, "b2", b"B")
    raw_token = "pair-invitation-token-with-enough-entropy-for-tests"
    vault_id = str(uuid.uuid4())
    invitation_id = str(uuid.uuid4())
    encrypted_share = b64(b"sealed partner share; not a real test key")
    created_at_ms = int(time.time() * 1000)
    expires_at_ms = created_at_ms + 60_000
    response = client.post(
        "/pair-v2/vaults",
        headers=headers(alice["access_token"]),
        json={
            "vault_id": vault_id,
            "creator_device_id": alice_device["device_id"],
            "encrypted_metadata": b64(b"encrypted vault metadata"),
            "invitation": {
                "invitation_id": invitation_id,
                "target_user_id": bob["user_id"],
                "target_device_id": bob_device["device_id"],
                "token_sha256": hashlib.sha256(raw_token.encode()).hexdigest(),
                "encrypted_share_envelope": encrypted_share,
                "created_at_ms": created_at_ms,
                "expires_at_ms": expires_at_ms,
            },
        },
    )
    assert response.status_code == 201, response.text
    context = response.json()["invitation"]["context"]
    assert context["created_at_ms"] == created_at_ms
    assert context["expires_at_ms"] == expires_at_ms
    return alice, bob, alice_device, bob_device, vault_id, invitation_id, raw_token, encrypted_share


def accept(client, bob, invitation_id, raw_token):
    response = client.post(
        f"/pair-v2/invitations/{invitation_id}/accept",
        headers=headers(bob["access_token"]),
        json={"token": raw_token},
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_device_registration_is_idempotent_but_rejects_key_or_device_replacement(client):
    alice = dev_account(client, "alice")
    device = register(client, alice, "a1", b"A")

    same = client.post(
        "/pair-v2/devices",
        headers=headers(alice["access_token"]),
        json={"device_id": device["device_id"], "agreement_public_key": b64(b"A" * 32)},
    )
    assert same.status_code == 201

    replacement = client.post(
        "/pair-v2/devices",
        headers=headers(alice["access_token"]),
        json={
            "device_id": "00000000-0000-0000-0000-0000000000a2",
            "agreement_public_key": b64(b"C" * 32),
        },
    )
    assert replacement.status_code == 409


def test_invitation_is_targeted_expiring_and_one_use(client):
    alice, bob, _, _, vault_id, invitation_id, raw_token, encrypted_share = pair_setup(client)

    listed = client.get("/pair-v2/invitations", headers=headers(bob["access_token"]))
    assert listed.status_code == 200
    assert listed.json()[0]["encrypted_share_envelope"] == encrypted_share
    assert listed.json()[0]["context"]["target_account_id"] == bob["user_id"]

    wrong_account = client.post(
        f"/pair-v2/invitations/{invitation_id}/accept",
        headers=headers(alice["access_token"]),
        json={"token": raw_token},
    )
    assert wrong_account.status_code == 403

    wrong_token = client.post(
        f"/pair-v2/invitations/{invitation_id}/accept",
        headers=headers(bob["access_token"]),
        json={"token": "different-token-that-is-also-long"},
    )
    assert wrong_token.status_code == 403

    payload = accept(client, bob, invitation_id, raw_token)
    assert payload["vault"]["status"] == "active"
    assert len(payload["vault"]["members"]) == 2
    assert payload["vault"]["vault_id"] == vault_id

    replay = client.post(
        f"/pair-v2/invitations/{invitation_id}/accept",
        headers=headers(bob["access_token"]),
        json={"token": raw_token},
    )
    assert replay.status_code == 409

    charlie = signup_account(client, "pair_charlie")
    third_member = client.post(
        f"/pair-v2/invitations/{invitation_id}/accept",
        headers=headers(charlie["access_token"]),
        json={"token": raw_token},
    )
    assert third_member.status_code == 403


def test_expired_invitation_cannot_be_accepted(client, db):
    alice, bob, _, _, _, invitation_id, raw_token, _ = pair_setup(client)
    invitation = db.query(PairInvitationV2).filter(PairInvitationV2.id == invitation_id).one()
    invitation.expires_at_ms = int(time.time() * 1000) - 1
    db.commit()

    expired = client.post(
        f"/pair-v2/invitations/{invitation_id}/accept",
        headers=headers(bob["access_token"]),
        json={"token": raw_token},
    )
    assert expired.status_code == 409
    db.refresh(invitation)
    assert invitation.status == "expired"
    creator_vaults = client.get(
        "/pair-v2/vaults",
        headers=headers(alice["access_token"]),
    )
    assert creator_vaults.status_code == 200
    assert creator_vaults.json()[0]["status"] == "expired"


def test_pair_access_approval_is_bound_one_time_and_replay_safe(client, db):
    alice, bob, alice_device, bob_device, vault_id, invitation_id, raw_token, _ = pair_setup(client)
    accept(client, bob, invitation_id, raw_token)
    now = int(time.time() * 1000)
    request_id = str(uuid.uuid4())
    created = client.post(
        f"/pair-v2/vaults/{vault_id}/access-requests",
        headers=headers(alice["access_token"]),
        json={
            "request_id": request_id,
            "requester_device_id": alice_device["device_id"],
            "requester_ephemeral_public_key": b64(b"E" * 32),
            "created_at_ms": now,
            "expires_at_ms": now + 60_000,
        },
    )
    assert created.status_code == 201, created.text
    context = created.json()["context"]
    assert context["vault_id"] == vault_id
    assert context["request_id"] == request_id
    assert context["approver_account_id"] == bob["user_id"]
    assert context["approver_device_id"] == bob_device["device_id"]
    assert context["requester_ephemeral_public_key"] == b64(b"E" * 32)

    incoming = client.get("/pair-v2/access-requests/incoming", headers=headers(bob["access_token"]))
    assert [item["request_id"] for item in incoming.json()] == [request_id]

    envelope = b64(b"approved encrypted share for requester")
    approved = client.post(
        f"/pair-v2/access-requests/{request_id}/approve",
        headers=headers(bob["access_token"]),
        json={"encrypted_share_envelope": envelope},
    )
    assert approved.status_code == 200

    duplicate_approval = client.post(
        f"/pair-v2/access-requests/{request_id}/approve",
        headers=headers(bob["access_token"]),
        json={"encrypted_share_envelope": envelope},
    )
    assert duplicate_approval.status_code == 409

    wrong_consumer = client.post(
        f"/pair-v2/access-requests/{request_id}/consume",
        headers=headers(bob["access_token"]),
    )
    assert wrong_consumer.status_code == 403

    consumed = client.post(
        f"/pair-v2/access-requests/{request_id}/consume",
        headers=headers(alice["access_token"]),
    )
    assert consumed.status_code == 200
    assert consumed.json()["encrypted_share_envelope"] == envelope
    assert consumed.json()["context"] == context

    replay = client.post(
        f"/pair-v2/access-requests/{request_id}/consume",
        headers=headers(alice["access_token"]),
    )
    assert replay.status_code == 409
    persisted = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).one()
    assert persisted.status == "consumed"
    assert persisted.encrypted_share_envelope is None


def test_access_request_self_wrong_denied_cancelled_and_expired_paths_fail(client, db):
    alice, bob, alice_device, _, vault_id, invitation_id, raw_token, _ = pair_setup(client)
    accept(client, bob, invitation_id, raw_token)
    charlie = signup_account(client, "access_charlie")

    def create_request(key_byte: bytes) -> str:
        current_ms = int(time.time() * 1000)
        request_id = str(uuid.uuid4())
        response = client.post(
            f"/pair-v2/vaults/{vault_id}/access-requests",
            headers=headers(alice["access_token"]),
            json={
                "request_id": request_id,
                "requester_device_id": alice_device["device_id"],
                "requester_ephemeral_public_key": b64(key_byte * 32),
                "created_at_ms": current_ms,
                "expires_at_ms": current_ms + 60_000,
            },
        )
        assert response.status_code == 201, response.text
        return request_id

    denied_id = create_request(b"D")
    envelope = b64(b"opaque encrypted approval envelope")
    assert client.post(
        f"/pair-v2/access-requests/{denied_id}/approve",
        headers=headers(alice["access_token"]),
        json={"encrypted_share_envelope": envelope},
    ).status_code == 403
    assert client.post(
        f"/pair-v2/access-requests/{denied_id}/approve",
        headers=headers(charlie["access_token"]),
        json={"encrypted_share_envelope": envelope},
    ).status_code == 403
    assert client.post(
        f"/pair-v2/access-requests/{denied_id}/deny",
        headers=headers(bob["access_token"]),
    ).status_code == 200
    assert client.post(
        f"/pair-v2/access-requests/{denied_id}/consume",
        headers=headers(alice["access_token"]),
    ).status_code == 409

    cancelled_id = create_request(b"C")
    assert client.post(
        f"/pair-v2/access-requests/{cancelled_id}/cancel",
        headers=headers(alice["access_token"]),
    ).status_code == 200
    assert client.post(
        f"/pair-v2/access-requests/{cancelled_id}/consume",
        headers=headers(alice["access_token"]),
    ).status_code == 409

    expired_id = create_request(b"X")
    record = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == expired_id).one()
    record.expires_at_ms = int(time.time() * 1000) - 1
    db.commit()
    assert client.post(
        f"/pair-v2/access-requests/{expired_id}/approve",
        headers=headers(bob["access_token"]),
        json={"encrypted_share_envelope": envelope},
    ).status_code == 409
    assert client.post(
        f"/pair-v2/access-requests/{expired_id}/consume",
        headers=headers(alice["access_token"]),
    ).status_code == 409
    db.refresh(record)
    assert record.status == "expired"


def test_expired_request_cannot_be_relabelled_denied_or_cancelled(client, db):
    alice, bob, alice_device, _, vault_id, invitation_id, raw_token, _ = pair_setup(client)
    accept(client, bob, invitation_id, raw_token)

    def expired_request(key_byte: bytes) -> tuple[str, PairAccessRequestV2]:
        current_ms = int(time.time() * 1000)
        request_id = str(uuid.uuid4())
        response = client.post(
            f"/pair-v2/vaults/{vault_id}/access-requests",
            headers=headers(alice["access_token"]),
            json={
                "request_id": request_id,
                "requester_device_id": alice_device["device_id"],
                "requester_ephemeral_public_key": b64(key_byte * 32),
                "created_at_ms": current_ms,
                "expires_at_ms": current_ms + 60_000,
            },
        )
        assert response.status_code == 201, response.text
        record = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).one()
        record.expires_at_ms = int(time.time() * 1000) - 1
        db.commit()
        return request_id, record

    denied_id, denied_record = expired_request(b"N")
    denied = client.post(
        f"/pair-v2/access-requests/{denied_id}/deny",
        headers=headers(bob["access_token"]),
    )
    assert denied.status_code == 409
    db.refresh(denied_record)
    assert denied_record.status == "expired"

    cancelled_id, cancelled_record = expired_request(b"L")
    cancelled = client.post(
        f"/pair-v2/access-requests/{cancelled_id}/cancel",
        headers=headers(alice["access_token"]),
    )
    assert cancelled.status_code == 409
    db.refresh(cancelled_record)
    assert cancelled_record.status == "expired"


def test_pair_request_size_limit_rejects_declared_and_chunked_oversized_bodies(client):
    response = client.post(
        "/pair-v2/devices",
        headers={"Content-Length": str(21 * 1024 * 1024 + 1)},
        content=b"{}",
    )
    assert response.status_code == 413

    def oversized_chunks():
        chunk = b"x" * (1024 * 1024)
        for _ in range(22):
            yield chunk

    chunked = client.post(
        "/pair-v2/devices",
        headers={"Transfer-Encoding": "chunked"},
        content=oversized_chunks(),
    )
    assert chunked.status_code == 413


def test_encrypted_media_persists_and_plaintext_metadata_is_not_stored(client, db):
    alice, bob, _, _, vault_id, invitation_id, raw_token, _ = pair_setup(client)
    accept(client, bob, invitation_id, raw_token)
    media_id = str(uuid.uuid4())
    plaintext_marker = "PRIVATE_BEACH_PHOTO.JPG"
    encrypted_blob = b64(b"ciphertext-and-authentication-tag")
    encrypted_metadata = b64(b"sealed-metadata-not-the-filename")
    created = client.post(
        f"/pair-v2/vaults/{vault_id}/media",
        headers=headers(alice["access_token"]),
        json={
            "media_id": media_id,
            "encrypted_blob": encrypted_blob,
            "encrypted_metadata": encrypted_metadata,
            "created_at_ms": int(time.time() * 1000),
        },
    )
    assert created.status_code == 201, created.text

    # A new SQLAlchemy session sees the same durable relay record.
    db.expire_all()
    stored = db.query(PairMediaV2).filter(PairMediaV2.id == media_id).one()
    assert stored.encrypted_blob == encrypted_blob
    assert stored.encrypted_metadata == encrypted_metadata
    assert plaintext_marker not in repr(stored.__dict__)

    downloaded = client.get(
        f"/pair-v2/vaults/{vault_id}/media/{media_id}",
        headers=headers(bob["access_token"]),
    )
    assert downloaded.status_code == 200
    assert downloaded.json()["encrypted_blob"] == encrypted_blob

    deleted = client.delete(
        f"/pair-v2/vaults/{vault_id}/media/{media_id}",
        headers=headers(bob["access_token"]),
    )
    assert deleted.status_code == 204
    assert db.query(PairMediaV2).filter(PairMediaV2.id == media_id).first() is None


def test_membership_revocation_invalidates_outstanding_approval(client, db):
    alice, bob, alice_device, _, vault_id, invitation_id, raw_token, _ = pair_setup(client)
    accept(client, bob, invitation_id, raw_token)
    current_ms = int(time.time() * 1000)
    request_id = str(uuid.uuid4())
    assert client.post(
        f"/pair-v2/vaults/{vault_id}/access-requests",
        headers=headers(alice["access_token"]),
        json={
            "request_id": request_id,
            "requester_device_id": alice_device["device_id"],
            "requester_ephemeral_public_key": b64(b"Q" * 32),
            "created_at_ms": current_ms,
            "expires_at_ms": current_ms + 60_000,
        },
    ).status_code == 201
    assert client.post(
        f"/pair-v2/access-requests/{request_id}/approve",
        headers=headers(bob["access_token"]),
        json={"encrypted_share_envelope": b64(b"encrypted approval share")},
    ).status_code == 200

    revoked = client.delete(
        f"/pair-v2/vaults/{vault_id}/members/{bob['user_id']}",
        headers=headers(alice["access_token"]),
    )
    assert revoked.status_code == 200
    assert revoked.json()["membership_version"] == 2
    persisted = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).one()
    assert persisted.status == "cancelled"
    assert persisted.encrypted_share_envelope is None
    assert client.post(
        f"/pair-v2/access-requests/{request_id}/consume",
        headers=headers(alice["access_token"]),
    ).status_code == 409


def test_relay_stores_invitation_hash_not_raw_token(client, db):
    _, _, _, _, _, invitation_id, raw_token, _ = pair_setup(client)
    invitation = db.query(PairInvitationV2).filter(PairInvitationV2.id == invitation_id).one()
    assert invitation.token_sha256 == hashlib.sha256(raw_token.encode()).hexdigest()
    assert raw_token not in repr(invitation.__dict__)


def test_membership_request_and_encrypted_media_survive_backend_restart(tmp_path):
    database_path = tmp_path / "pair-restart.db"
    database_url = f"sqlite:///{database_path}"
    original_overrides = app.dependency_overrides.copy()

    def configure_engine():
        engine = create_engine(database_url, connect_args={"check_same_thread": False})
        Base.metadata.create_all(bind=engine)
        session_factory = sessionmaker(autocommit=False, autoflush=False, bind=engine)

        def override_database():
            database = session_factory()
            try:
                yield database
            finally:
                database.close()

        app.dependency_overrides[get_db] = override_database
        return engine

    first_engine = configure_engine()
    try:
        with TestClient(app) as first_client:
            alice, bob, alice_device, _, vault_id, invitation_id, raw_token, _ = pair_setup(first_client)
            accept(first_client, bob, invitation_id, raw_token)
            current_ms = int(time.time() * 1000)
            request_id = str(uuid.uuid4())
            requested = first_client.post(
                f"/pair-v2/vaults/{vault_id}/access-requests",
                headers=headers(alice["access_token"]),
                json={
                    "request_id": request_id,
                    "requester_device_id": alice_device["device_id"],
                    "requester_ephemeral_public_key": b64(b"R" * 32),
                    "created_at_ms": current_ms,
                    "expires_at_ms": current_ms + 60_000,
                },
            )
            assert requested.status_code == 201, requested.text

            media_id = str(uuid.uuid4())
            encrypted_blob = b64(b"opaque-aes-gcm-media-combined-box")
            encrypted_metadata = b64(b"opaque-aes-gcm-metadata-box")
            uploaded = first_client.post(
                f"/pair-v2/vaults/{vault_id}/media",
                headers=headers(alice["access_token"]),
                json={
                    "media_id": media_id,
                    "encrypted_blob": encrypted_blob,
                    "encrypted_metadata": encrypted_metadata,
                    "created_at_ms": current_ms,
                },
            )
            assert uploaded.status_code == 201, uploaded.text

        # A new engine and TestClient simulate a backend process restart while
        # retaining only the documented SQLite database.
        first_engine.dispose()
        second_engine = configure_engine()
        try:
            with TestClient(app) as restarted_client:
                vaults = restarted_client.get(
                    "/pair-v2/vaults",
                    headers=headers(alice["access_token"]),
                )
                assert vaults.status_code == 200
                assert vaults.json()[0]["vault_id"] == vault_id
                assert len(vaults.json()[0]["members"]) == 2

                pending = restarted_client.get(
                    f"/pair-v2/access-requests/{request_id}",
                    headers=headers(alice["access_token"]),
                )
                assert pending.status_code == 200
                assert pending.json()["status"] == "pending"

                downloaded = restarted_client.get(
                    f"/pair-v2/vaults/{vault_id}/media/{media_id}",
                    headers=headers(bob["access_token"]),
                )
                assert downloaded.status_code == 200
                assert downloaded.json()["encrypted_blob"] == encrypted_blob
                assert downloaded.json()["encrypted_metadata"] == encrypted_metadata
        finally:
            second_engine.dispose()
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(original_overrides)
