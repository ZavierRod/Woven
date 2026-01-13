from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class FriendRequestCreate(BaseModel):
    """Request body for sending a friend request."""
    invite_code: str


class FriendResponse(BaseModel):
    """Simplified friend info for lists."""
    id: int
    username: str
    full_name: Optional[str] = None
    invite_code: Optional[str] = None
    profile_picture_url: Optional[str] = None

    class Config:
        from_attributes = True


class FriendshipResponse(BaseModel):
    """Friendship data returned in API responses."""
    id: int
    user_id: int
    friend_id: int
    status: str
    created_at: datetime
    friend: Optional[FriendResponse] = None

    class Config:
        from_attributes = True


class FriendListResponse(BaseModel):
    """Response for the friends list endpoint."""
    friends: List[FriendResponse]
    total: int


class PendingRequestResponse(BaseModel):
    """A single pending friend request with requester info."""
    id: int
    user_id: int
    status: str
    created_at: datetime
    requester: Optional[FriendResponse] = None

    class Config:
        from_attributes = True


class PendingRequestsResponse(BaseModel):
    """Response for pending friend requests endpoint."""
    requests: List[PendingRequestResponse]
    total: int
