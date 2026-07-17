"""Authenticated development relay for the Woven Pair Vault v2 protocol."""

import base64
import binascii
import hmac

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_access_token, get_current_user_id
from app.crud.user import user_crud
from app.deps import get_db
from app.models.pair_v2 import (
    PairAccessRequestV2,
    PairDeviceV2,
    PairInvitationV2,
    PairMediaV2,
    PairMemberV2,
    PairVaultV2,
)
from app.models.user import User
from app.schemas.auth import SignUpRequest
from app.schemas.pair_v2 import (
    AccessApprovalV2,
    AccessRequestCreateV2,
    DeviceRegistrationV2,
    InvitationAcceptV2,
    PairMediaCreateV2,
    PairVaultCreateV2,
)
from app.services.pair_v2 import (
    access_context,
    active_members,
    expire_request_if_needed,
    now_ms,
    require_active_pair_vault,
    token_hash,
)

router = APIRouter(prefix="/pair-v2", tags=["Pair Vault v2"])

MAX_INVITATION_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000
MAX_ACCESS_LIFETIME_MS = 5 * 60 * 1000
MAX_CLOCK_SKEW_MS = 2 * 60 * 1000
MAX_ENCRYPTED_MEDIA_BYTES = 15 * 1024 * 1024


def conflict(message: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=message)


def validate_public_key(value: str) -> None:
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=422, detail="Agreement public key must be valid Base64")
    if len(raw) != 32:
        raise HTTPException(status_code=422, detail="Agreement public key must contain 32 bytes")


def device_payload(device: PairDeviceV2) -> dict:
    return {
        "device_id": device.id,
        "user_id": device.user_id,
        "agreement_public_key": device.agreement_public_key,
        "created_at_ms": device.created_at_ms,
    }


def invitation_context(invitation: PairInvitationV2) -> dict:
    return {
        "protocol": "woven-pair-v2",
        "purpose": "invitation-share",
        "vault_id": invitation.vault_id,
        "invitation_id": invitation.id,
        "membership_version": invitation.membership_version,
        "creator_account_id": invitation.creator_user_id,
        "creator_device_id": invitation.creator_device_id,
        "target_account_id": invitation.target_user_id,
        "target_device_id": invitation.target_device_id,
        "created_at_ms": invitation.created_at_ms,
        "expires_at_ms": invitation.expires_at_ms,
    }


def invitation_payload(invitation: PairInvitationV2, include_envelope: bool = True) -> dict:
    payload = {
        "invitation_id": invitation.id,
        "vault_id": invitation.vault_id,
        "status": invitation.status,
        "context": invitation_context(invitation),
    }
    if include_envelope:
        payload["encrypted_share_envelope"] = invitation.encrypted_share_envelope
    return payload


def request_payload(request: PairAccessRequestV2, include_envelope: bool = False) -> dict:
    payload = {
        "request_id": request.id,
        "vault_id": request.vault_id,
        "status": request.status,
        "context": access_context(request),
    }
    if include_envelope and request.encrypted_share_envelope is not None:
        payload["encrypted_share_envelope"] = request.encrypted_share_envelope
    return payload


def vault_payload(db: Session, vault: PairVaultV2) -> dict:
    members = active_members(db, vault.id)
    return {
        "vault_id": vault.id,
        "encrypted_metadata": vault.encrypted_metadata,
        "membership_version": vault.membership_version,
        "status": vault.status,
        "created_at_ms": vault.created_at_ms,
        "members": [
            {
                "user_id": member.user_id,
                "device_id": member.device_id,
                "role": member.role,
                "status": member.status,
            }
            for member in members
        ],
    }


@router.post("/dev/session/{account}")
def development_session(account: str, db: Session = Depends(get_db)):
    """Return a JWT for one of two deterministic local-development accounts."""
    if not settings.DEBUG:
        raise HTTPException(status_code=404, detail="Not found")
    normalized = account.lower()
    if normalized not in {"alice", "bob"}:
        raise HTTPException(status_code=404, detail="Development account must be alice or bob")
    username = f"pair_{normalized}"
    user = user_crud.get_by_username(db, username)
    if user is None:
        user = user_crud.create(
            db,
            SignUpRequest(
                username=username,
                email=f"{username}@example.com",
                password=f"woven-{normalized}-development",
                full_name=normalized.title(),
            ),
        )
    return {
        "access_token": create_access_token({"sub": str(user.id)}),
        "token_type": "bearer",
        "user_id": user.id,
        "username": user.username,
        "email": user.email,
        "full_name": user.full_name,
        "invite_code": user.invite_code,
    }


@router.post("/devices", status_code=status.HTTP_201_CREATED)
def register_device(
    request: DeviceRegistrationV2,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    validate_public_key(request.agreement_public_key)
    existing_for_user = db.query(PairDeviceV2).filter(
        PairDeviceV2.user_id == user_id,
        PairDeviceV2.revoked.is_(False),
    ).first()
    if existing_for_user is not None:
        if (
            existing_for_user.id == request.device_id
            and hmac.compare_digest(existing_for_user.agreement_public_key, request.agreement_public_key)
        ):
            return device_payload(existing_for_user)
        raise conflict("This account already has an active Pair device")
    if db.query(PairDeviceV2).filter(PairDeviceV2.id == request.device_id).first() is not None:
        raise conflict("Device identifier is already registered")
    device = PairDeviceV2(
        id=request.device_id,
        user_id=user_id,
        agreement_public_key=request.agreement_public_key,
        created_at_ms=now_ms(),
        revoked=False,
    )
    db.add(device)
    db.commit()
    return device_payload(device)


@router.get("/devices/users/{target_user_id}")
def lookup_device(
    target_user_id: int,
    _: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    device = db.query(PairDeviceV2).filter(
        PairDeviceV2.user_id == target_user_id,
        PairDeviceV2.revoked.is_(False),
    ).first()
    if device is None:
        raise HTTPException(status_code=404, detail="Pair device not found")
    return device_payload(device)


@router.post("/vaults", status_code=status.HTTP_201_CREATED)
def create_pair_vault(
    request: PairVaultCreateV2,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    current_ms = now_ms()
    invitation = request.invitation
    if invitation.target_user_id == user_id:
        raise HTTPException(status_code=422, detail="A Pair vault requires two different accounts")
    if abs(invitation.created_at_ms - current_ms) > MAX_CLOCK_SKEW_MS:
        raise HTTPException(status_code=422, detail="Invitation creation time is outside the clock-skew window")
    if invitation.expires_at_ms <= current_ms or invitation.expires_at_ms > invitation.created_at_ms + MAX_INVITATION_LIFETIME_MS:
        raise HTTPException(status_code=422, detail="Invitation expiry is outside the allowed window")
    creator_device = db.query(PairDeviceV2).filter(
        PairDeviceV2.id == request.creator_device_id,
        PairDeviceV2.user_id == user_id,
        PairDeviceV2.revoked.is_(False),
    ).first()
    target_device = db.query(PairDeviceV2).filter(
        PairDeviceV2.id == invitation.target_device_id,
        PairDeviceV2.user_id == invitation.target_user_id,
        PairDeviceV2.revoked.is_(False),
    ).first()
    if creator_device is None or target_device is None:
        raise HTTPException(status_code=422, detail="Both accounts must have registered Pair devices")
    if db.query(User).filter(User.id == invitation.target_user_id).first() is None:
        raise HTTPException(status_code=404, detail="Target account not found")
    if db.query(PairVaultV2).filter(PairVaultV2.id == request.vault_id).first() is not None:
        raise conflict("Vault identifier was already used")
    if db.query(PairInvitationV2).filter(PairInvitationV2.id == invitation.invitation_id).first() is not None:
        raise conflict("Invitation identifier was already used")

    vault = PairVaultV2(
        id=request.vault_id,
        creator_user_id=user_id,
        encrypted_metadata=request.encrypted_metadata,
        membership_version=1,
        status="pending",
        created_at_ms=invitation.created_at_ms,
        updated_at_ms=current_ms,
    )
    member = PairMemberV2(
        vault_id=request.vault_id,
        user_id=user_id,
        device_id=request.creator_device_id,
        role="creator",
        status="active",
        joined_at_ms=current_ms,
    )
    invitation_record = PairInvitationV2(
        id=invitation.invitation_id,
        vault_id=request.vault_id,
        creator_user_id=user_id,
        creator_device_id=request.creator_device_id,
        target_user_id=invitation.target_user_id,
        target_device_id=invitation.target_device_id,
        token_sha256=invitation.token_sha256,
        encrypted_share_envelope=invitation.encrypted_share_envelope,
        membership_version=1,
        status="pending",
        # Preserve the client timestamp because it is authenticated AEAD context.
        created_at_ms=invitation.created_at_ms,
        expires_at_ms=invitation.expires_at_ms,
    )
    db.add_all([vault, member, invitation_record])
    db.commit()
    return {
        "vault": vault_payload(db, vault),
        "invitation": invitation_payload(invitation_record, include_envelope=False),
    }


@router.get("/invitations")
def list_invitations(
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    current_ms = now_ms()
    invitations = db.query(PairInvitationV2).filter(PairInvitationV2.target_user_id == user_id).all()
    changed = False
    for invitation in invitations:
        if invitation.status == "pending" and invitation.expires_at_ms <= current_ms:
            invitation.status = "expired"
            changed = True
    if changed:
        db.commit()
    return [invitation_payload(invitation) for invitation in invitations if invitation.status == "pending"]


@router.post("/invitations/{invitation_id}/accept")
def accept_invitation(
    invitation_id: str,
    request: InvitationAcceptV2,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    invitation = db.query(PairInvitationV2).filter(PairInvitationV2.id == invitation_id).with_for_update().first()
    if invitation is None:
        raise HTTPException(status_code=404, detail="Invitation not found")
    if invitation.target_user_id != user_id:
        raise HTTPException(status_code=403, detail="Invitation belongs to another account")
    if invitation.status != "pending":
        raise conflict(f"Invitation is already {invitation.status}")
    current_ms = now_ms()
    if invitation.expires_at_ms <= current_ms:
        invitation.status = "expired"
        db.commit()
        raise conflict("Invitation expired")
    if not hmac.compare_digest(invitation.token_sha256, token_hash(request.token)):
        raise HTTPException(status_code=403, detail="Invitation token is invalid")
    vault = db.query(PairVaultV2).filter(PairVaultV2.id == invitation.vault_id).with_for_update().first()
    members = active_members(db, invitation.vault_id)
    if vault is None or vault.status != "pending" or len(members) != 1:
        raise conflict("Invitation no longer matches the Pair membership")
    if db.query(PairMemberV2).filter(PairMemberV2.vault_id == vault.id, PairMemberV2.user_id == user_id).first():
        raise conflict("Account is already a member")
    transitioned = db.query(PairInvitationV2).filter(
        PairInvitationV2.id == invitation_id,
        PairInvitationV2.status == "pending",
    ).update(
        {
            PairInvitationV2.status: "accepted",
            PairInvitationV2.accepted_at_ms: current_ms,
        },
        synchronize_session=False,
    )
    if transitioned != 1:
        db.rollback()
        raise conflict("Invitation was already resolved")
    db.add(
        PairMemberV2(
            vault_id=vault.id,
            user_id=user_id,
            device_id=invitation.target_device_id,
            role="partner",
            status="active",
            joined_at_ms=current_ms,
        )
    )
    vault.status = "active"
    vault.updated_at_ms = current_ms
    db.commit()
    db.refresh(invitation)
    return {
        "vault": vault_payload(db, vault),
        "invitation": invitation_payload(invitation),
    }


@router.post("/invitations/{invitation_id}/cancel")
def cancel_invitation(
    invitation_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    invitation = db.query(PairInvitationV2).filter(PairInvitationV2.id == invitation_id).with_for_update().first()
    if invitation is None:
        raise HTTPException(status_code=404, detail="Invitation not found")
    if invitation.creator_user_id != user_id:
        raise HTTPException(status_code=403, detail="Only the creator can cancel this invitation")
    if invitation.status != "pending":
        raise conflict(f"Invitation is already {invitation.status}")
    invitation.status = "cancelled"
    invitation.encrypted_share_envelope = "cancelled"
    vault = db.query(PairVaultV2).filter(PairVaultV2.id == invitation.vault_id).first()
    if vault is not None:
        vault.status = "cancelled"
        vault.updated_at_ms = now_ms()
    db.commit()
    return {"status": "cancelled"}


@router.get("/vaults")
def list_pair_vaults(
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    memberships = db.query(PairMemberV2).filter(
        PairMemberV2.user_id == user_id,
        PairMemberV2.status == "active",
    ).all()
    vaults = db.query(PairVaultV2).filter(PairVaultV2.id.in_([member.vault_id for member in memberships])).all() if memberships else []
    current_ms = now_ms()
    changed = False
    for vault in vaults:
        if vault.status != "pending":
            continue
        invitation = db.query(PairInvitationV2).filter(
            PairInvitationV2.vault_id == vault.id,
        ).first()
        if invitation is not None and (
            invitation.status == "expired"
            or (invitation.status == "pending" and invitation.expires_at_ms <= current_ms)
        ):
            if invitation.status == "pending":
                invitation.status = "expired"
            vault.status = "expired"
            vault.updated_at_ms = current_ms
            changed = True
    if changed:
        db.commit()
    return [vault_payload(db, vault) for vault in vaults]


@router.get("/vaults/{vault_id}")
def get_pair_vault(
    vault_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    membership = db.query(PairMemberV2).filter(
        PairMemberV2.vault_id == vault_id,
        PairMemberV2.user_id == user_id,
        PairMemberV2.status == "active",
    ).first()
    vault = db.query(PairVaultV2).filter(PairVaultV2.id == vault_id).first()
    if vault is None:
        raise HTTPException(status_code=404, detail="Pair vault not found")
    if membership is None:
        raise HTTPException(status_code=403, detail="Pair membership required")
    return vault_payload(db, vault)


@router.post("/vaults/{vault_id}/access-requests", status_code=status.HTTP_201_CREATED)
def create_access_request(
    vault_id: str,
    request: AccessRequestCreateV2,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    validate_public_key(request.requester_ephemeral_public_key)
    vault, membership = require_active_pair_vault(db, vault_id, user_id)
    if membership.device_id != request.requester_device_id:
        raise HTTPException(status_code=403, detail="Requester device does not match membership")
    current_ms = now_ms()
    if abs(request.created_at_ms - current_ms) > MAX_CLOCK_SKEW_MS:
        raise HTTPException(status_code=422, detail="Request creation time is outside the clock-skew window")
    if request.expires_at_ms <= current_ms or request.expires_at_ms > request.created_at_ms + MAX_ACCESS_LIFETIME_MS:
        raise HTTPException(status_code=422, detail="Access request expiry is outside the allowed window")
    if db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request.request_id).first() is not None:
        raise conflict("Access request identifier was already used")
    outstanding = db.query(PairAccessRequestV2).filter(
        PairAccessRequestV2.vault_id == vault_id,
        PairAccessRequestV2.requester_user_id == user_id,
        PairAccessRequestV2.status.in_(["pending", "approved"]),
    ).first()
    if outstanding is not None and outstanding.expires_at_ms > current_ms:
        raise conflict("Requester already has an outstanding access request")
    members = active_members(db, vault_id)
    approver = next(member for member in members if member.user_id != user_id)
    record = PairAccessRequestV2(
        id=request.request_id,
        vault_id=vault_id,
        requester_user_id=user_id,
        requester_device_id=request.requester_device_id,
        approver_user_id=approver.user_id,
        approver_device_id=approver.device_id,
        requester_ephemeral_public_key=request.requester_ephemeral_public_key,
        membership_version=vault.membership_version,
        status="pending",
        created_at_ms=request.created_at_ms,
        expires_at_ms=request.expires_at_ms,
    )
    db.add(record)
    db.commit()
    return request_payload(record)


@router.get("/access-requests/incoming")
def incoming_access_requests(
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    records = db.query(PairAccessRequestV2).filter(
        PairAccessRequestV2.approver_user_id == user_id,
        PairAccessRequestV2.status == "pending",
    ).all()
    changed = False
    current_ms = now_ms()
    for record in records:
        changed = expire_request_if_needed(record, current_ms) or changed
    if changed:
        db.commit()
    return [request_payload(record) for record in records if record.status == "pending"]


@router.get("/access-requests/{request_id}")
def get_access_request(
    request_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    record = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).first()
    if record is None:
        raise HTTPException(status_code=404, detail="Access request not found")
    if user_id not in {record.requester_user_id, record.approver_user_id}:
        raise HTTPException(status_code=403, detail="Access request belongs to other members")
    if expire_request_if_needed(record, now_ms()):
        db.commit()
    return request_payload(record)


@router.post("/access-requests/{request_id}/approve")
def approve_access_request(
    request_id: str,
    approval: AccessApprovalV2,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    record = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).with_for_update().first()
    if record is None:
        raise HTTPException(status_code=404, detail="Access request not found")
    if record.approver_user_id != user_id:
        raise HTTPException(status_code=403, detail="Only the designated member can approve")
    if expire_request_if_needed(record, now_ms()):
        db.commit()
        raise conflict("Access request expired")
    vault, membership = require_active_pair_vault(db, record.vault_id, user_id)
    if membership.device_id != record.approver_device_id or vault.membership_version != record.membership_version:
        raise conflict("Pair membership changed")
    if record.status != "pending":
        raise conflict(f"Access request is already {record.status}")
    responded_at_ms = now_ms()
    transitioned = db.query(PairAccessRequestV2).filter(
        PairAccessRequestV2.id == request_id,
        PairAccessRequestV2.status == "pending",
    ).update(
        {
            PairAccessRequestV2.status: "approved",
            PairAccessRequestV2.encrypted_share_envelope: approval.encrypted_share_envelope,
            PairAccessRequestV2.responded_at_ms: responded_at_ms,
        },
        synchronize_session=False,
    )
    if transitioned != 1:
        db.rollback()
        raise conflict("Access request was already resolved")
    db.commit()
    db.refresh(record)
    return request_payload(record)


@router.post("/access-requests/{request_id}/deny")
def deny_access_request(
    request_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    record = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).with_for_update().first()
    if record is None:
        raise HTTPException(status_code=404, detail="Access request not found")
    if record.approver_user_id != user_id:
        raise HTTPException(status_code=403, detail="Only the designated member can deny")
    if expire_request_if_needed(record, now_ms()):
        db.commit()
        raise conflict("Access request expired")
    if record.status != "pending":
        raise conflict(f"Access request is already {record.status}")
    transitioned = db.query(PairAccessRequestV2).filter(
        PairAccessRequestV2.id == request_id,
        PairAccessRequestV2.status == "pending",
    ).update(
        {
            PairAccessRequestV2.status: "denied",
            PairAccessRequestV2.responded_at_ms: now_ms(),
        },
        synchronize_session=False,
    )
    if transitioned != 1:
        db.rollback()
        raise conflict("Access request was already resolved")
    db.commit()
    return {"status": "denied"}


@router.post("/access-requests/{request_id}/consume")
def consume_access_request(
    request_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    record = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).with_for_update().first()
    if record is None:
        raise HTTPException(status_code=404, detail="Access request not found")
    if record.requester_user_id != user_id:
        raise HTTPException(status_code=403, detail="Only the requester can consume approval")
    if expire_request_if_needed(record, now_ms()):
        db.commit()
        raise conflict("Access request expired")
    vault, membership = require_active_pair_vault(db, record.vault_id, user_id)
    if membership.device_id != record.requester_device_id or vault.membership_version != record.membership_version:
        raise conflict("Pair membership changed")
    if record.status != "approved" or record.encrypted_share_envelope is None:
        raise conflict(f"Access request cannot be consumed from {record.status}")
    envelope = record.encrypted_share_envelope
    context = access_context(record)
    transitioned = db.query(PairAccessRequestV2).filter(
        PairAccessRequestV2.id == request_id,
        PairAccessRequestV2.status == "approved",
        PairAccessRequestV2.encrypted_share_envelope.is_not(None),
    ).update(
        {
            PairAccessRequestV2.status: "consumed",
            PairAccessRequestV2.consumed_at_ms: now_ms(),
            PairAccessRequestV2.encrypted_share_envelope: None,
        },
        synchronize_session=False,
    )
    if transitioned != 1:
        db.rollback()
        raise conflict("Access request was already consumed or resolved")
    db.commit()
    return {"status": "consumed", "context": context, "encrypted_share_envelope": envelope}


@router.post("/access-requests/{request_id}/cancel")
def cancel_access_request(
    request_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    record = db.query(PairAccessRequestV2).filter(PairAccessRequestV2.id == request_id).with_for_update().first()
    if record is None:
        raise HTTPException(status_code=404, detail="Access request not found")
    if record.requester_user_id != user_id:
        raise HTTPException(status_code=403, detail="Only the requester can cancel")
    if expire_request_if_needed(record, now_ms()):
        db.commit()
        raise conflict("Access request expired")
    if record.status not in {"pending", "approved"}:
        raise conflict(f"Access request is already {record.status}")
    transitioned = db.query(PairAccessRequestV2).filter(
        PairAccessRequestV2.id == request_id,
        PairAccessRequestV2.status.in_(["pending", "approved"]),
    ).update(
        {
            PairAccessRequestV2.status: "cancelled",
            PairAccessRequestV2.encrypted_share_envelope: None,
            PairAccessRequestV2.responded_at_ms: now_ms(),
        },
        synchronize_session=False,
    )
    if transitioned != 1:
        db.rollback()
        raise conflict("Access request was already resolved")
    db.commit()
    return {"status": "cancelled"}


@router.delete("/vaults/{vault_id}/members/{target_user_id}")
def revoke_pair_member(
    vault_id: str,
    target_user_id: int,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    vault, membership = require_active_pair_vault(db, vault_id, user_id)
    if membership.role != "creator" and target_user_id != user_id:
        raise HTTPException(status_code=403, detail="Only the creator can revoke another member")
    target = db.query(PairMemberV2).filter(
        PairMemberV2.vault_id == vault_id,
        PairMemberV2.user_id == target_user_id,
        PairMemberV2.status == "active",
    ).with_for_update().first()
    if target is None:
        raise HTTPException(status_code=404, detail="Active member not found")
    target.status = "revoked"
    vault.membership_version += 1
    vault.status = "revoked"
    vault.updated_at_ms = now_ms()
    outstanding = db.query(PairAccessRequestV2).filter(
        PairAccessRequestV2.vault_id == vault_id,
        PairAccessRequestV2.status.in_(["pending", "approved"]),
    ).all()
    for record in outstanding:
        record.status = "cancelled"
        record.encrypted_share_envelope = None
    db.commit()
    return {"status": "revoked", "membership_version": vault.membership_version}


@router.post("/vaults/{vault_id}/media", status_code=status.HTTP_201_CREATED)
def upload_pair_media(
    vault_id: str,
    request: PairMediaCreateV2,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    require_active_pair_vault(db, vault_id, user_id)
    try:
        encrypted_bytes = base64.b64decode(request.encrypted_blob, validate=True)
        base64.b64decode(request.encrypted_metadata, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=422, detail="Encrypted media fields must be valid Base64")
    if len(encrypted_bytes) > MAX_ENCRYPTED_MEDIA_BYTES:
        raise HTTPException(status_code=413, detail="Encrypted media exceeds the development limit")
    if db.query(PairMediaV2).filter(PairMediaV2.id == request.media_id).first() is not None:
        raise conflict("Media identifier was already used")
    record = PairMediaV2(
        id=request.media_id,
        vault_id=vault_id,
        uploader_user_id=user_id,
        encrypted_blob=request.encrypted_blob,
        encrypted_metadata=request.encrypted_metadata,
        created_at_ms=request.created_at_ms,
    )
    db.add(record)
    db.commit()
    return {
        "media_id": record.id,
        "vault_id": record.vault_id,
        "encrypted_metadata": record.encrypted_metadata,
        "created_at_ms": record.created_at_ms,
    }


@router.get("/vaults/{vault_id}/media")
def list_pair_media(
    vault_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    require_active_pair_vault(db, vault_id, user_id)
    records = db.query(PairMediaV2).filter(PairMediaV2.vault_id == vault_id).all()
    return [
        {
            "media_id": record.id,
            "vault_id": record.vault_id,
            "encrypted_metadata": record.encrypted_metadata,
            "created_at_ms": record.created_at_ms,
        }
        for record in records
    ]


@router.get("/vaults/{vault_id}/media/{media_id}")
def download_pair_media(
    vault_id: str,
    media_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    require_active_pair_vault(db, vault_id, user_id)
    record = db.query(PairMediaV2).filter(PairMediaV2.id == media_id, PairMediaV2.vault_id == vault_id).first()
    if record is None:
        raise HTTPException(status_code=404, detail="Encrypted media not found")
    return {
        "media_id": record.id,
        "vault_id": record.vault_id,
        "encrypted_blob": record.encrypted_blob,
        "encrypted_metadata": record.encrypted_metadata,
        "created_at_ms": record.created_at_ms,
    }


@router.delete("/vaults/{vault_id}/media/{media_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_pair_media(
    vault_id: str,
    media_id: str,
    user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    require_active_pair_vault(db, vault_id, user_id)
    record = db.query(PairMediaV2).filter(PairMediaV2.id == media_id, PairMediaV2.vault_id == vault_id).first()
    if record is None:
        raise HTTPException(status_code=404, detail="Encrypted media not found")
    db.delete(record)
    db.commit()
    return None
