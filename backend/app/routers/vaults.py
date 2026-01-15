from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID

from app.deps import get_db
from app.core.security import get_current_user_id
from app.crud.vault import vault_crud, vault_member_crud
from app.crud.user import user_crud
from app.crud.friendship import friendship_crud
from app.schemas.vault import (
    VaultCreate,
    VaultUpdate,
    VaultResponse,
    VaultDetailResponse,
    VaultMemberResponse,
    VaultInviteRequest,
    VaultInviteResponse,
)
from app.schemas.user import UserResponse
from app.models.vault import MemberRole, MemberStatus, VaultStatus

router = APIRouter(prefix="/vaults", tags=["Vaults"])


def vault_to_response(db: Session, vault) -> VaultResponse:
    """Convert Vault model to VaultResponse."""
    return VaultResponse(
        id=vault.id,
        name=vault.name,
        type=vault.type.value,
        mode=vault.mode.value,
        status=vault.status.value,
        owner_id=vault.owner_id,
        created_at=vault.created_at,
        updated_at=vault.updated_at,
        last_accessed_at=vault.last_accessed_at,
        member_count=vault_crud.get_member_count(db, vault.id),
        media_count=vault_crud.get_media_count(db, vault.id),
    )


def vault_to_detail_response(db: Session, vault) -> VaultDetailResponse:
    """Convert Vault model to VaultDetailResponse with members."""
    members = vault_member_crud.get_vault_members(db, vault.id)

    member_responses = []
    for member in members:
        user = user_crud.get_by_id(db, member.user_id)
        member_responses.append(VaultMemberResponse(
            id=member.id,
            user_id=member.user_id,
            user=UserResponse.model_validate(user) if user else None,
            role=member.role.value,
            status=member.status.value,
            joined_at=member.joined_at,
        ))

    owner = user_crud.get_by_id(db, vault.owner_id)

    return VaultDetailResponse(
        id=vault.id,
        name=vault.name,
        type=vault.type.value,
        mode=vault.mode.value,
        owner_id=vault.owner_id,
        owner=UserResponse.model_validate(owner) if owner else None,
        created_at=vault.created_at,
        updated_at=vault.updated_at,
        last_accessed_at=vault.last_accessed_at,
        member_count=len(
            [m for m in members if m.status == MemberStatus.ACCEPTED]),
        media_count=vault_crud.get_media_count(db, vault.id),
        members=member_responses,
    )


@router.post("/", response_model=VaultResponse, status_code=status.HTTP_201_CREATED)
async def create_vault(
    vault_in: VaultCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Create a new vault.
    
    - **name**: Display name for the vault
    - **type**: "solo" (default) or "pair"
    - **mode**: "normal" (default) or "strict"
    - **invitee_id**: Required if type is "pair"
    """
    # Validate pair vault requirements
    if vault_in.type == "pair":
        if not vault_in.invitee_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="invitee_id is required for pair vaults"
            )
            
        # Check if users are friends using friendship_crud
        if not friendship_crud.are_friends(db, current_user_id, vault_in.invitee_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="You can only create a pair vault with a friend"
            )
            
        # Check if invitee exists
        invitee = user_crud.get_by_id(db, vault_in.invitee_id)
        if not invitee:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Invited user not found"
            )

        # Create vault in PENDING state
        vault = vault_crud.create(db, vault_in, current_user_id, status="PENDING")
        
        # Add invitee as PENDING member
        vault_member_crud.add_member(
            db,
            vault.id,
            invitee.id,
            role=MemberRole.MEMBER,
            status=MemberStatus.PENDING
        )
        
        # Send push notification
        from app.services.apns import apns_service
        from app.crud.device import device_crud
        
        # Get invitee's devices
        devices = device_crud.get_user_devices(db, invitee.id)
        
        # Get current user info
        sender = user_crud.get_by_id(db, current_user_id)
        sender_name = sender.full_name or sender.username
        
        async def send_pushes():
            for device in devices:
                await apns_service.send_notification(
                    device_token=device.token,
                    title="Vault Invitation",
                    body=f"{sender_name} invited you to a shared vault",
                    data={"type": "vault_invite", "vault_id": str(vault.id)},
                    environment=device.apns_environment or "sandbox"
                )
        
        background_tasks.add_task(send_pushes)
        
    else:
        # Solo vault - created ACTIVE
        vault = vault_crud.create(db, vault_in, current_user_id, status="ACTIVE")

    return vault_to_response(db, vault)


@router.get("/", response_model=List[VaultResponse])
def list_vaults(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Get all vaults the current user owns or is a member of."""
    vaults = vault_crud.get_user_vaults(db, current_user_id)
    return [vault_to_response(db, v) for v in vaults]


@router.get("/{vault_id}", response_model=VaultDetailResponse)
def get_vault(
    vault_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Get vault details including members."""
    vault = vault_crud.get_by_id(db, vault_id)

    if not vault:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vault not found"
        )

    if not vault_crud.can_access(db, vault_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this vault"
        )

    # Update last accessed
    vault_crud.update_last_accessed(db, vault)

    return vault_to_detail_response(db, vault)


@router.patch("/{vault_id}", response_model=VaultResponse)
def update_vault(
    vault_id: UUID,
    vault_update: VaultUpdate,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Update vault settings.

    Only the vault owner can update settings.
    """
    vault = vault_crud.get_by_id(db, vault_id)

    if not vault:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vault not found"
        )

    if not vault_crud.is_owner(db, vault_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the vault owner can update settings"
        )

    updated_vault = vault_crud.update(db, vault, vault_update)
    return vault_to_response(db, updated_vault)


@router.delete("/{vault_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_vault(
    vault_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Delete a vault.

    Only the vault owner can delete. This permanently removes all vault data.
    """
    vault = vault_crud.get_by_id(db, vault_id)

    if not vault:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vault not found"
        )

    if not vault_crud.is_owner(db, vault_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the vault owner can delete the vault"
        )

    vault_crud.delete(db, vault)
    return None


@router.post("/{vault_id}/invite", response_model=VaultInviteResponse)
async def invite_to_vault(
    vault_id: UUID,
    invite: VaultInviteRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Invite a user to a pair vault using their invite code.

    - Only works for "pair" type vaults
    - Pair vaults can have max 2 members
    """
    vault = vault_crud.get_by_id(db, vault_id)

    if not vault:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vault not found"
        )

    if not vault_crud.is_owner(db, vault_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the vault owner can invite members"
        )

    if vault.type.value != "pair":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only pair vaults can have invited members"
        )

    # Check if vault already has 2 members
    member_count = vault_crud.get_member_count(db, vault_id)
    if member_count >= 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Pair vault already has maximum members"
        )

    # Find user by invite code
    invited_user = user_crud.get_by_invite_code(db, invite.invite_code)
    if not invited_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found with that invite code"
        )

    if invited_user.id == current_user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot invite yourself"
        )

    # Check if users are friends
    if not friendship_crud.are_friends(db, current_user_id, invited_user.id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You can only invite friends to your vault"
        )

    # Check if user is already a member
    if vault_crud.is_member(db, vault_id, invited_user.id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User is already a member of this vault"
        )

    # Add as pending member
    vault_member_crud.add_member(
        db,
        vault_id,
        invited_user.id,
        role=MemberRole.MEMBER,
        status=MemberStatus.PENDING
    )

    # Send push notification to invited user
    from app.services.apns import apns_service
    from app.crud.device import device_crud
    
    # Get invited user's devices
    devices = device_crud.get_user_devices(db, invited_user.id)
    
    # Get current user info for the message
    sender = user_crud.get_by_id(db, current_user_id)
    sender_name = sender.full_name or sender.username
    
    async def send_pushes():
        for device in devices:
            await apns_service.send_notification(
                device_token=device.token,
                title="Vault Invitation",
                body=f"{sender_name} invited you to a shared vault",
                data={"type": "vault_invite", "vault_id": str(vault_id)},
                environment=device.apns_environment or "sandbox"
            )
            
    background_tasks.add_task(send_pushes)

    return VaultInviteResponse(
        vault_id=vault_id,
        invited_user_id=invited_user.id,
        status="pending",
        message=f"Invitation sent to {invited_user.full_name or 'user'}"
    )


@router.get("/invites/pending", response_model=List[VaultDetailResponse])
def get_pending_invites(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Get vaults where the current user has a pending invitation."""
    pending_memberships = vault_member_crud.get_pending_invites(
        db, current_user_id)

    vaults = []
    for membership in pending_memberships:
        vault = vault_crud.get_by_id(db, membership.vault_id)
        if vault:
            vaults.append(vault_to_detail_response(db, vault))

    return vaults


@router.post("/{vault_id}/accept", response_model=VaultResponse)
def accept_vault_invite(
    vault_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Accept a pending vault invitation."""
    # Find pending membership
    pending_memberships = vault_member_crud.get_pending_invites(
        db, current_user_id)
    membership = next(
        (m for m in pending_memberships if m.vault_id == vault_id),
        None
    )

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No pending invitation found for this vault"
        )

    vault_member_crud.accept_membership(db, membership)
    
    # Activate the vault if it was pending
    vault = vault_crud.get_by_id(db, vault_id)
    if vault.status == VaultStatus.PENDING:
        vault.status = VaultStatus.ACTIVE
        db.commit()
        db.refresh(vault)
        
    return vault_to_response(db, vault)


@router.post("/{vault_id}/decline", status_code=status.HTTP_204_NO_CONTENT)
def decline_vault_invite(
    vault_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Decline a pending vault invitation."""
    pending_memberships = vault_member_crud.get_pending_invites(
        db, current_user_id)
    membership = next(
        (m for m in pending_memberships if m.vault_id == vault_id),
        None
    )

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No pending invitation found for this vault"
        )

    vault_member_crud.remove_member(db, membership)
    return None


@router.delete("/{vault_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
def leave_vault(
    vault_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Leave a vault (for non-owners).

    Owners must delete the vault instead.
    """
    vault = vault_crud.get_by_id(db, vault_id)

    if not vault:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Vault not found"
        )

    if vault_crud.is_owner(db, vault_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Vault owner cannot leave. Delete the vault instead."
        )

    # Find membership
    members = vault_member_crud.get_vault_members(db, vault_id)
    membership = next(
        (m for m in members if m.user_id == current_user_id),
        None
    )

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="You are not a member of this vault"
        )

    vault_member_crud.remove_member(db, membership)
    return None
