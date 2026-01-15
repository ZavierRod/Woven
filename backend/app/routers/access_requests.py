from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from sqlalchemy.orm import Session
from uuid import UUID

from app.deps import get_db
from app.core.security import get_current_user_id
from app.crud.access_request import access_request_crud
from app.crud.vault import vault_crud, vault_member_crud
from app.crud.user import user_crud
from app.crud.device import device_crud
from app.schemas.access_request import AccessRequestCreate, AccessRequestResponse, AccessRequestApprove
from app.services.apns import apns_service
from app.models.vault import VaultMode

router = APIRouter(prefix="/access-requests", tags=["Access Requests"])

@router.post("/", response_model=AccessRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_access_request(
    request: AccessRequestCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Request access to a Strict Mode vault.
    Sends a push notification to the partner to approve.
    """
    # 1. Verify Vault exists and mode is STRICT
    vault = vault_crud.get_by_id(db, request.vault_id)
    if not vault:
        raise HTTPException(status_code=404, detail="Vault not found")
    
    if vault.mode != VaultMode.STRICT:
        raise HTTPException(status_code=400, detail="Access requests are only for Strict Mode vaults")

    # 2. Verify user is a member/owner
    if not vault_crud.can_access(db, vault.id, current_user_id):
        raise HTTPException(status_code=403, detail="You are not a member of this vault")

    # 3. Find the "other" member (the approver)
    members = vault_member_crud.get_accepted_members(db, vault.id)
    # In a pair vault, there should be 2 members.
    approver_member = next((m for m in members if m.user_id != current_user_id), None)
    
    if not approver_member:
        raise HTTPException(status_code=400, detail="No partner found in this vault to approve request")
    
    approver_id = approver_member.user_id

    # 4. Create Access Request
    access_req = access_request_crud.create(
        db, request, requester_id=current_user_id, approver_id=approver_id
    )

    # 5. Send Push to Approver
    approver_devices = device_crud.get_user_devices(db, approver_id)
    requester_user = user_crud.get_by_id(db, current_user_id)
    requester_name = requester_user.full_name or requester_user.username
    
    async def send_approval_push():
        for device in approver_devices:
            await apns_service.send_notification(
                device_token=device.token,
                title="Unlock Request",
                body=f"{requester_name} wants to open '{vault.name}'",
                data={
                    "type": "access_request", 
                    "request_id": access_req.id,
                    "vault_id": str(vault.id),
                    "requester_public_key": request.requester_public_key
                },
                environment=device.apns_environment or "sandbox"
            )

    background_tasks.add_task(send_approval_push)

    return access_req


@router.post("/{request_id}/approve", response_model=AccessRequestResponse)
async def approve_access_request(
    request_id: int,
    approval_data: AccessRequestApprove,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Approve an access request by providing the encrypted key share.
    """
    access_req = access_request_crud.get(db, request_id)
    if not access_req:
        raise HTTPException(status_code=404, detail="Request not found")

    # Verify user is the assigned approver
    if access_req.approver_id != current_user_id:
        raise HTTPException(status_code=403, detail="You are not authorized to approve this request")

    # Update request
    updated_req = access_request_crud.approve(db, access_req, approval_data.encrypted_share)

    # Send Push to Requester (Optional, but good UX)
    requester_devices = device_crud.get_user_devices(db, access_req.requester_id)
    
    async def send_approved_push():
        for device in requester_devices:
            await apns_service.send_notification(
                device_token=device.token,
                title="Access Approved",
                body="You can now open the vault.",
                data={
                    "type": "request_approved",
                    "request_id": access_req.id,
                    "vault_id": str(access_req.vault_id),
                    "encrypted_share": approval_data.encrypted_share
                },
                environment=device.apns_environment or "sandbox"
            )
            
    background_tasks.add_task(send_approved_push)

    return updated_req


@router.post("/{request_id}/deny", response_model=AccessRequestResponse)
async def deny_access_request(
    request_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Deny an access request.
    """
    access_req = access_request_crud.get(db, request_id)
    if not access_req:
        raise HTTPException(status_code=404, detail="Request not found")

    if access_req.approver_id != current_user_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    result = access_request_crud.deny(db, access_req)
    
    # Send notification to requester
    requester_devices = device_crud.get_user_devices(db, access_req.requester_id)
    vault = vault_crud.get_by_id(db, access_req.vault_id)
    
    async def send_denied_push():
        for device in requester_devices:
            await apns_service.send_notification(
                device_token=device.token,
                title="Access Denied",
                body=f"Your request to open '{vault.name}' was denied.",
                data={
                    "type": "request_denied",
                    "request_id": access_req.id,
                    "vault_id": str(access_req.vault_id)
                },
                environment=device.apns_environment or "sandbox"
            )
    
    background_tasks.add_task(send_denied_push)
    
    return result



@router.get("/{request_id}", response_model=AccessRequestResponse)
def get_access_request(
    request_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Poll for status.
    """
    access_req = access_request_crud.get(db, request_id)
    if not access_req:
        raise HTTPException(status_code=404, detail="Request not found")

    # Only requester or approver can view
    if current_user_id not in [access_req.requester_id, access_req.approver_id]:
        raise HTTPException(status_code=403, detail="Not authorized")

    return access_req
