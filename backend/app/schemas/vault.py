from pydantic import BaseModel
from typing import Optional, List, Literal
from datetime import datetime
from uuid import UUID

from app.schemas.user import UserResponse


class VaultCreate(BaseModel):
    """Request body for creating a vault."""
    name: str
    type: Literal["solo", "pair"] = "solo"
    mode: Literal["normal", "strict"] = "normal"


class VaultUpdate(BaseModel):
    """Request body for updating a vault."""
    name: Optional[str] = None
    mode: Optional[Literal["normal", "strict"]] = None


class VaultMemberResponse(BaseModel):
    """Vault member in API responses."""
    id: int
    user_id: int
    user: Optional[UserResponse] = None
    role: str
    status: str
    joined_at: Optional[datetime] = None
    
    class Config:
        from_attributes = True


class VaultResponse(BaseModel):
    """Vault in API responses (list view)."""
    id: UUID
    name: str
    type: str
    mode: str
    owner_id: int
    created_at: datetime
    updated_at: Optional[datetime] = None
    last_accessed_at: Optional[datetime] = None
    member_count: int = 0
    media_count: int = 0
    
    class Config:
        from_attributes = True


class VaultDetailResponse(VaultResponse):
    """Vault with full details (detail view)."""
    owner: Optional[UserResponse] = None
    members: List[VaultMemberResponse] = []


class VaultInviteRequest(BaseModel):
    """Request to invite a user to a pair vault."""
    invite_code: str  # The friend's invite code


class VaultInviteResponse(BaseModel):
    """Response after inviting someone to a vault."""
    vault_id: UUID
    invited_user_id: int
    status: str
    message: str


