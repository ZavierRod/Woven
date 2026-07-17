"""Canonical Ed25519 verification for authenticated Pair Vault requests."""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import time
from typing import Optional

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import get_current_user_id
from app.deps import get_db
from app.models.pair_v2 import PairDeviceRequestNonceV2, PairDeviceV2

PROTOCOL = "woven-pair-v2"
HEADER_PREFIX = "x-woven-"


def canonical_request(
    *,
    method: str,
    path: str,
    request_id: str,
    account_id: int,
    device_id: str,
    vault_id: Optional[str],
    timestamp_ms: int,
    nonce: str,
    body: bytes,
) -> bytes:
    """Return the only byte representation accepted by server and clients."""
    fields = {
        "account_id": account_id,
        "body_sha256": hashlib.sha256(body).hexdigest(),
        "device_id": device_id,
        "http_method": method.upper(),
        "nonce": nonce,
        "path": path,
        "protocol": PROTOCOL,
        "request_id": request_id,
        "timestamp_ms": timestamp_ms,
        "vault_id": vault_id or "",
    }
    return json.dumps(fields, sort_keys=True, separators=(",", ":")).encode("utf-8")


def verify_signature(public_key_b64: str, signature_b64: str, message: bytes) -> None:
    try:
        public_key = base64.b64decode(public_key_b64, validate=True)
        signature = base64.b64decode(signature_b64, validate=True)
        Ed25519PublicKey.from_public_bytes(public_key).verify(signature, message)
    except (ValueError, binascii.Error, InvalidSignature) as error:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid device signature") from error


async def require_signed_device_request(
    request: Request,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
) -> Optional[str]:
    """Verify binding, freshness, and one-time use before sensitive Pair work."""
    if not settings.ENFORCE_DEVICE_SIGNATURES:
        return None

    headers = request.headers
    protocol = headers.get(f"{HEADER_PREFIX}protocol", "")
    device_id = headers.get(f"{HEADER_PREFIX}device-id", "")
    request_id = headers.get(f"{HEADER_PREFIX}request-id", "")
    timestamp_value = headers.get(f"{HEADER_PREFIX}timestamp-ms", "")
    nonce = headers.get(f"{HEADER_PREFIX}nonce", "")
    vault_id = headers.get(f"{HEADER_PREFIX}vault-id", "")
    signature = headers.get(f"{HEADER_PREFIX}signature", "")
    if protocol != PROTOCOL or not all((device_id, request_id, timestamp_value, nonce, signature)):
        raise HTTPException(status_code=401, detail="Missing device signature")
    if len(request_id) > 64 or len(nonce) > 128:
        raise HTTPException(status_code=401, detail="Invalid device signature")
    try:
        timestamp_ms = int(timestamp_value)
    except ValueError as error:
        raise HTTPException(status_code=401, detail="Invalid device signature") from error

    now = int(time.time() * 1000)
    if abs(now - timestamp_ms) > settings.DEVICE_SIGNATURE_CLOCK_SKEW_SECONDS * 1000:
        raise HTTPException(status_code=401, detail="Expired device signature")

    route_vault_id = request.path_params.get("vault_id")
    if route_vault_id is not None and vault_id != route_vault_id:
        raise HTTPException(status_code=401, detail="Invalid device signature binding")
    if route_vault_id is None and vault_id:
        raise HTTPException(status_code=401, detail="Invalid device signature binding")

    device = db.query(PairDeviceV2).filter(
        PairDeviceV2.id == device_id,
        PairDeviceV2.user_id == user_id,
        PairDeviceV2.revoked.is_(False),
    ).first()
    if device is None:
        raise HTTPException(status_code=401, detail="Unknown or revoked device")

    body = await request.body()
    message = canonical_request(
        method=request.method,
        path=request.url.path,
        request_id=request_id,
        account_id=user_id,
        device_id=device_id,
        vault_id=vault_id or None,
        timestamp_ms=timestamp_ms,
        nonce=nonce,
        body=body,
    )
    verify_signature(device.signing_public_key, signature, message)

    replay = PairDeviceRequestNonceV2(
        device_id=device_id,
        nonce=nonce,
        request_id=request_id,
        timestamp_ms=timestamp_ms,
        created_at_ms=now,
    )
    try:
        db.add(replay)
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=409, detail="Device request replay rejected") from error
    return device_id
