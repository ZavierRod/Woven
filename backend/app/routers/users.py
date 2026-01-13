from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from app.deps import get_db
from app.schemas.user import UserResponse
from app.crud.user import user_crud
from app.core.security import get_current_user_id

router = APIRouter(prefix="/users", tags=["Users"])


class UserUpdate(BaseModel):
    """Request body for updating user profile."""
    full_name: Optional[str] = None


@router.get("/me", response_model=UserResponse)
def get_current_user(
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """Get the currently authenticated user's profile."""
    user = user_crud.get_by_id(db, current_user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    return user


@router.patch("/me", response_model=UserResponse)
def update_current_user(
    update: UserUpdate,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)
):
    """Update the currently authenticated user's profile."""
    user = user_crud.get_by_id(db, current_user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    if update.full_name is not None:
        user = user_crud.update_name(db, user, update.full_name)

    return user


@router.get("/{invite_code}", response_model=UserResponse)
def get_user_by_invite_code(
    invite_code: str,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id)  # Require auth
):
    """Get a user by their invite code (for adding friends)."""
    user = user_crud.get_by_invite_code(db, invite_code)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found with that invite code"
        )
    return user
