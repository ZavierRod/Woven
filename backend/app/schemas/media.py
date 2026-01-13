from pydantic import BaseModel
from typing import Optional, Literal
from datetime import datetime
from uuid import UUID

from app.schemas.user import UserResponse


class MediaUploadRequest(BaseModel):
    """Request to get upload URL for media."""
    vault_id: UUID
    file_name: str
    file_size: int  # Size in bytes
    media_type: Literal["photo", "video"]
    encryption_iv: str  # Base64 encoded IV
    encryption_tag: str  # Base64 encoded authentication tag


class MediaUploadResponse(BaseModel):
    """Response with upload URL and media ID."""
    media_id: UUID
    upload_url: str
    expires_in: int  # Seconds until URL expires


class MediaCreate(BaseModel):
    """Request to register uploaded media."""
    vault_id: UUID
    storage_key: str
    file_name: str
    file_size: int
    media_type: Literal["photo", "video"]
    encryption_iv: str
    encryption_tag: str
    thumbnail_key: Optional[str] = None


class MediaResponse(BaseModel):
    """Media metadata in API responses."""
    id: UUID
    vault_id: UUID
    media_type: str
    file_name: str
    file_size: int
    uploaded_by_id: int
    uploaded_by: Optional[UserResponse] = None
    created_at: datetime
    
    class Config:
        from_attributes = True


class MediaViewUrlResponse(BaseModel):
    """Response with temporary view URL for media."""
    view_url: str
    expires_in: int  # Seconds until URL expires


class MediaListResponse(BaseModel):
    """List of media in a vault."""
    media: list[MediaResponse]
    total: int


