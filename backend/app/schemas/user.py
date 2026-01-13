from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class UserBase(BaseModel):
    username: Optional[str] = None
    email: Optional[str] = None
    full_name: Optional[str] = None


class UserCreate(UserBase):
    """For internal use - creating users."""
    password_hash: str
    invite_code: Optional[str] = None


class UserResponse(BaseModel):
    """User data returned in API responses."""
    id: int
    username: str
    email: str
    full_name: Optional[str] = None
    invite_code: Optional[str] = None
    profile_picture_url: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
