import uuid
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Enum as SQLEnum, BigInteger
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum

from app.db.session import Base


class MediaType(str, enum.Enum):
    PHOTO = "photo"
    VIDEO = "video"


class VaultMedia(Base):
    """
    Encrypted media stored in a vault.
    
    Media is encrypted on-device before upload. The server only stores
    encrypted blobs and metadata. Media can only be viewed in-app (view-only).
    """
    __tablename__ = "vault_media"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    vault_id = Column(UUID(as_uuid=True), ForeignKey("vaults.id", ondelete="CASCADE"), nullable=False)
    uploaded_by_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    
    # Media metadata
    media_type = Column(SQLEnum(MediaType), nullable=False)
    file_name = Column(String, nullable=False)  # Original filename
    file_size = Column(BigInteger, nullable=False)  # Size in bytes (encrypted)
    
    # Storage
    storage_key = Column(String, nullable=False, unique=True)  # Path/key in storage
    encryption_iv = Column(String, nullable=False)  # AES-GCM initialization vector (base64)
    encryption_tag = Column(String, nullable=False)  # AES-GCM authentication tag (base64)
    
    # Optional thumbnail for faster loading
    thumbnail_key = Column(String, nullable=True)  # Path/key for thumbnail if available
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    vault = relationship("Vault", back_populates="media")
    uploaded_by = relationship("User")

    def __repr__(self):
        return f"<VaultMedia(id={self.id}, type={self.media_type}, vault_id={self.vault_id})>"


