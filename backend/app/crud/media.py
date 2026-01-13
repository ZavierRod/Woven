from sqlalchemy.orm import Session
from typing import Optional, List
from uuid import UUID

from app.models.media import VaultMedia, MediaType
from app.schemas.media import MediaCreate
from app.services.storage import storage_service


class MediaCRUD:
    """CRUD operations for VaultMedia."""
    
    def get_by_id(self, db: Session, media_id: UUID) -> Optional[VaultMedia]:
        """Get media by ID."""
        return db.query(VaultMedia).filter(VaultMedia.id == media_id).first()
    
    def get_by_vault(self, db: Session, vault_id: UUID) -> List[VaultMedia]:
        """Get all media in a vault, ordered by creation date (newest first)."""
        return db.query(VaultMedia).filter(
            VaultMedia.vault_id == vault_id
        ).order_by(VaultMedia.created_at.desc()).all()
    
    def create(self, db: Session, media_in: MediaCreate, uploaded_by_id: int) -> VaultMedia:
        """Create a new media record."""
        media = VaultMedia(
            vault_id=media_in.vault_id,
            uploaded_by_id=uploaded_by_id,
            media_type=MediaType(media_in.media_type),
            file_name=media_in.file_name,
            file_size=media_in.file_size,
            storage_key=media_in.storage_key,
            encryption_iv=media_in.encryption_iv,
            encryption_tag=media_in.encryption_tag,
            thumbnail_key=media_in.thumbnail_key,
        )
        db.add(media)
        db.commit()
        db.refresh(media)
        return media
    
    def delete(self, db: Session, media_id: UUID) -> bool:
        """Delete media record and file."""
        media = self.get_by_id(db, media_id)
        if not media:
            return False
        
        # Delete file from storage
        storage_service.delete_file(media.storage_key)
        if media.thumbnail_key:
            storage_service.delete_file(media.thumbnail_key)
        
        # Delete database record
        db.delete(media)
        db.commit()
        return True
    
    def can_access(self, db: Session, media_id: UUID, user_id: int) -> bool:
        """Check if user can access the media (must be vault member/owner)."""
        from app.crud.vault import vault_crud
        
        media = self.get_by_id(db, media_id)
        if not media:
            return False
        
        return vault_crud.can_access(db, media.vault_id, user_id)
    
    def count_by_vault(self, db: Session, vault_id: UUID) -> int:
        """Count media items in a vault."""
        return db.query(VaultMedia).filter(VaultMedia.vault_id == vault_id).count()


# Singleton instance
media_crud = MediaCRUD()


