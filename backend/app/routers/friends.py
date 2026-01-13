from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks
from sqlalchemy.orm import Session
from typing import List

from app.deps import get_db
from app.core.security import get_current_user_id
from app.crud.friendship import friendship_crud
from app.crud.user import user_crud
from app.schemas.friendship import (
    FriendRequestCreate,
    FriendResponse,
    FriendshipResponse,
    FriendListResponse,
    PendingRequestResponse,
    PendingRequestsResponse,
)

router = APIRouter(prefix="/friends", tags=["Friends"])


def user_to_friend_response(user) -> FriendResponse:
    """Convert User model to FriendResponse."""
    return FriendResponse(
        id=user.id,
        username=user.username,
        full_name=user.full_name,
        invite_code=user.invite_code,
        profile_picture_url=user.profile_picture_url,
    )


@router.post("/request", response_model=FriendshipResponse, status_code=status.HTTP_201_CREATED)
async def send_friend_request(
    request: FriendRequestCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Send a friend request to another user using their invite code.
    """
    # Look up user by invite code
    target_user = user_crud.get_by_invite_code(db, request.invite_code)
    if not target_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found with that invite code"
        )

    # Send the friend request
    try:
        friendship = friendship_crud.send_request(
            db, current_user_id, target_user.id)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )

    # Send push notification to recipient
    from app.services.apns import apns_service
    from app.crud.device import device_crud
    
    # Get target user's devices
    devices = device_crud.get_user_devices(db, target_user.id)
    
    # Get current user info for the message
    sender = user_crud.get_by_id(db, current_user_id)
    sender_name = sender.full_name or sender.username
    
    async def send_pushes():
        for device in devices:
            await apns_service.send_notification(
                device_token=device.token,
                title="New Friend Request",
                body=f"{sender_name} wants to connect",
                data={"type": "friend_request", "request_id": friendship.id},
                environment=device.apns_environment or "sandbox"
            )
            
    background_tasks.add_task(send_pushes)

    return FriendshipResponse(
        id=friendship.id,
        user_id=friendship.user_id,
        friend_id=friendship.friend_id,
        status=friendship.status,
        created_at=friendship.created_at,
        friend=user_to_friend_response(target_user),
    )


@router.get("/", response_model=FriendListResponse)
def get_friends(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Get the current user's friends list (accepted friendships only).
    """
    friends = friendship_crud.get_friends(db, current_user_id)

    return FriendListResponse(
        friends=[user_to_friend_response(f) for f in friends],
        total=len(friends),
    )


@router.get("/requests/pending", response_model=PendingRequestsResponse)
def get_pending_requests(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Get incoming friend requests waiting for the current user's response.
    """
    pending = friendship_crud.get_pending_requests(db, current_user_id)

    requests = []
    for friendship in pending:
        requester = user_crud.get_by_id(db, friendship.user_id)
        requests.append(PendingRequestResponse(
            id=friendship.id,
            user_id=friendship.user_id,
            status=friendship.status,
            created_at=friendship.created_at,
            requester=user_to_friend_response(
                requester) if requester else None,
        ))

    return PendingRequestsResponse(
        requests=requests,
        total=len(requests),
    )


@router.get("/requests/sent", response_model=PendingRequestsResponse)
def get_sent_requests(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Get outgoing friend requests sent by the current user.
    """
    sent = friendship_crud.get_sent_requests(db, current_user_id)

    requests = []
    for friendship in sent:
        target = user_crud.get_by_id(db, friendship.friend_id)
        requests.append(PendingRequestResponse(
            id=friendship.id,
            user_id=friendship.friend_id,
            status=friendship.status,
            created_at=friendship.created_at,
            requester=user_to_friend_response(target) if target else None,
        ))

    return PendingRequestsResponse(
        requests=requests,
        total=len(requests),
    )


@router.post("/requests/{friendship_id}/accept", response_model=FriendshipResponse)
def accept_friend_request(
    friendship_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Accept a pending friend request.
    """
    friendship = friendship_crud.accept_request(
        db, friendship_id, current_user_id)

    if not friendship:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found or you are not authorized to accept it"
        )

    # Get the requester's info
    requester = user_crud.get_by_id(db, friendship.user_id)

    return FriendshipResponse(
        id=friendship.id,
        user_id=friendship.user_id,
        friend_id=friendship.friend_id,
        status=friendship.status,
        created_at=friendship.created_at,
        friend=user_to_friend_response(requester) if requester else None,
    )


@router.post("/requests/{friendship_id}/decline", status_code=status.HTTP_204_NO_CONTENT)
def decline_friend_request(
    friendship_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Decline a pending friend request.
    """
    success = friendship_crud.decline_request(
        db, friendship_id, current_user_id)

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friend request not found or you are not authorized to decline it"
        )

    return None


@router.delete("/{friend_user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_friend(
    friend_user_id: int,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Remove an existing friend.
    """
    success = friendship_crud.remove_friend(
        db, current_user_id, friend_user_id)

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Friendship not found"
        )

    return None
