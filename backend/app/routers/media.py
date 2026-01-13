from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from fastapi.responses import FileResponse, StreamingResponse
from sqlalchemy.orm import Session
from typing import List
from uuid import UUID
import os

from app.deps import get_db
from app.core.security import get_current_user_id
from app.crud.media import media_crud
from app.crud.vault import vault_crud
from app.crud.user import user_crud
from app.schemas.user import UserResponse
from app.schemas.media import (
    MediaCreate,
    MediaResponse,
    MediaViewUrlResponse,
    MediaListResponse,
)
from app.services.storage import storage_service

router = APIRouter(prefix="/media", tags=["Media"])


def media_to_response(db: Session, media) -> MediaResponse:
    """Convert VaultMedia model to MediaResponse."""
    uploaded_by = user_crud.get_by_id(db, media.uploaded_by_id)
    
    return MediaResponse(
        id=media.id,
        vault_id=media.vault_id,
        media_type=media.media_type.value,
        file_name=media.file_name,
        file_size=media.file_size,
        uploaded_by_id=media.uploaded_by_id,
        uploaded_by=uploaded_by if uploaded_by else None,
        created_at=media.created_at,
    )


@router.post("/", response_model=MediaResponse, status_code=status.HTTP_201_CREATED)
def upload_media(
    vault_id: UUID = Form(...),
    file_name: str = Form(...),
    file_size: int = Form(...),
    media_type: str = Form(...),
    encryption_iv: str = Form(...),
    encryption_tag: str = Form(...),
    thumbnail_key: str = Form(None),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Upload encrypted media file.
    
    Client encrypts media on-device, then uploads encrypted blob here.
    The file is saved to storage and registered in the database.
    """
    # Verify user has access to vault
    if not vault_crud.can_access(db, vault_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this vault"
        )
    
    # Validate media type
    if media_type not in ["photo", "video"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="media_type must be 'photo' or 'video'"
        )
    
    # Generate media ID and storage key
    import uuid
    media_id = uuid.uuid4()
    storage_key = storage_service.generate_storage_key(
        str(vault_id),
        str(media_id),
        file_name
    )
    
    # Read file content
    file_content = file.file.read()
    
    # Verify file size matches
    if len(file_content) != file_size:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"File size mismatch: expected {file_size}, got {len(file_content)}"
        )
    
    # Save file to storage
    storage_service.save_file(storage_key, file_content)
    
    # Create media record
    media_in = MediaCreate(
        vault_id=vault_id,
        storage_key=storage_key,
        file_name=file_name,
        file_size=file_size,
        media_type=media_type,
        encryption_iv=encryption_iv,
        encryption_tag=encryption_tag,
        thumbnail_key=thumbnail_key,
    )
    
    media = media_crud.create(db, media_in, current_user_id)
    
    return media_to_response(db, media)


@router.get("/vault/{vault_id}", response_model=MediaListResponse)
def list_vault_media(
    vault_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """Get all media in a vault (metadata only)."""
    # Verify access
    if not vault_crud.can_access(db, vault_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this vault"
        )
    
    media_list = media_crud.get_by_vault(db, vault_id)
    
    return MediaListResponse(
        media=[media_to_response(db, m) for m in media_list],
        total=len(media_list)
    )


@router.get("/{media_id}/view-url", response_model=MediaViewUrlResponse)
def get_view_url(
    media_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Get a temporary URL for viewing media (view-only, expires quickly).
    
    This URL is for in-app viewing only. No download/save functionality.
    """
    # Check if media exists first
    media = media_crud.get_by_id(db, media_id)
    if not media:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media not found"
        )
    
    # Then verify access
    if not media_crud.can_access(db, media_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this media"
        )
    
    view_url, expires_in = storage_service.generate_view_url(media.storage_key)
    
    return MediaViewUrlResponse(
        view_url=f"/api{view_url}",
        expires_in=expires_in
    )




@router.get("/{media_id}/view")
def view_media_by_id(
    media_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    View media file by ID (view-only endpoint).
    
    Returns the encrypted media file as a stream. Client decrypts on-device.
    """
    # Check if media exists first
    media = media_crud.get_by_id(db, media_id)
    if not media:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media not found"
        )
    
    # Then verify access
    if not media_crud.can_access(db, media_id, current_user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this media"
        )
    
    # Get file from storage
    file_content = storage_service.get_file(media.storage_key)
    if not file_content:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media file not found in storage"
        )
    
    # Return as streaming response (prevents browser from suggesting download)
    return StreamingResponse(
        iter([file_content]),
        media_type="application/octet-stream",
        headers={
            "Content-Disposition": f'inline; filename="{media.file_name}"',
            "X-Content-Type-Options": "nosniff",
            "Content-Length": str(len(file_content)),
        }
    )


@router.delete("/{media_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_media(
    media_id: UUID,
    db: Session = Depends(get_db),
    current_user_id: int = Depends(get_current_user_id),
):
    """
    Delete media from vault.
    
    Only vault owner or the user who uploaded it can delete.
    """
    # Check if media exists first
    media = media_crud.get_by_id(db, media_id)
    if not media:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Media not found"
        )
    
    # Check if user is owner or uploader
    is_owner = vault_crud.is_owner(db, media.vault_id, current_user_id)
    is_uploader = media.uploaded_by_id == current_user_id
    
    if not (is_owner or is_uploader):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to delete this media"
        )
    
    success = media_crud.delete(db, media_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete media"
        )
    
    return None

