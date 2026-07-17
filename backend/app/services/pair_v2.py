"""Authorization and canonical-context helpers for Pair Vault v2."""

import hashlib
import time

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.models.pair_v2 import PairAccessRequestV2, PairDeviceV2, PairMemberV2, PairVaultV2


def now_ms() -> int:
    return int(time.time() * 1000)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def active_members(db: Session, vault_id: str) -> list[PairMemberV2]:
    return db.query(PairMemberV2).join(PairDeviceV2, PairDeviceV2.id == PairMemberV2.device_id).filter(
        PairMemberV2.vault_id == vault_id,
        PairMemberV2.status == "active",
        PairDeviceV2.revoked.is_(False),
    ).all()


def require_active_pair_vault(db: Session, vault_id: str, user_id: int) -> tuple[PairVaultV2, PairMemberV2]:
    vault = db.query(PairVaultV2).filter(PairVaultV2.id == vault_id).first()
    if vault is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Pair vault not found")
    membership = db.query(PairMemberV2).filter(
        PairMemberV2.vault_id == vault_id,
        PairMemberV2.user_id == user_id,
        PairMemberV2.status == "active",
    ).first()
    if membership is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Active Pair membership required")
    members = active_members(db, vault_id)
    if vault.status != "active" or len(members) != 2:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Pair vault requires exactly two active members")
    return vault, membership


def access_context(request: PairAccessRequestV2) -> dict:
    return {
        "protocol": "woven-pair-v2",
        "purpose": "access-share",
        "vault_id": request.vault_id,
        "request_id": request.id,
        "membership_version": request.membership_version,
        "requester_account_id": request.requester_user_id,
        "requester_device_id": request.requester_device_id,
        "requester_ephemeral_public_key": request.requester_ephemeral_public_key,
        "approver_account_id": request.approver_user_id,
        "approver_device_id": request.approver_device_id,
        "created_at_ms": request.created_at_ms,
        "expires_at_ms": request.expires_at_ms,
    }


def expire_request_if_needed(request: PairAccessRequestV2, current_ms: int) -> bool:
    if request.status in {"pending", "approved"} and request.expires_at_ms <= current_ms:
        request.status = "expired"
        request.encrypted_share_envelope = None
        return True
    return False
