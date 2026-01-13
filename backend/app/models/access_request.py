from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, Enum
from sqlalchemy.orm import relationship
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
import enum

from app.db.session import Base

class AccessRequestStatus(str, enum.Enum):
    PENDING = "pending"
    APPROVED = "approved"
    DENIED = "denied"
    EXPIRED = "expired"

class AccessRequest(Base):
    __tablename__ = "access_requests"

    id = Column(Integer, primary_key=True, index=True)
    vault_id = Column(UUID(as_uuid=True), ForeignKey("vaults.id"), nullable=False)
    requester_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    approver_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    
    status = Column(Enum(AccessRequestStatus), default=AccessRequestStatus.PENDING)
    
    # Ephemeral public key from requester (Base64) to encrypt the share with
    requester_public_key = Column(String, nullable=False)
    
    # Encrypted share from approver (Base64), only present if APPROVED
    encrypted_share = Column(String, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    expires_at = Column(DateTime, nullable=False)
    
    # Relationships
    vault = relationship("Vault", back_populates="access_requests")
    requester = relationship("User", foreign_keys=[requester_id])
    approver = relationship("User", foreign_keys=[approver_id])
