from pydantic import BaseModel
from typing import Optional
from datetime import datetime
from uuid import UUID
from app.models.access_request import AccessRequestStatus

# Shared properties
class AccessRequestBase(BaseModel):
    vault_id: UUID
    requester_public_key: str

# Properties to receive on creation
class AccessRequestCreate(AccessRequestBase):
    pass

# Properties to receive on approval
class AccessRequestApprove(BaseModel):
    encrypted_share: str

# Properties to return to client
class AccessRequestResponse(AccessRequestBase):
    id: int
    requester_id: int
    approver_id: int
    status: AccessRequestStatus
    encrypted_share: Optional[str] = None
    created_at: datetime
    expires_at: datetime

    class Config:
        from_attributes = True
