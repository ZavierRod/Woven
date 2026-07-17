import uuid

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.db.session import Base


class RefreshCredential(Base):
    """Hashed, rotating refresh credential. Raw secrets are never persisted."""

    __tablename__ = "refresh_credentials"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    family_id = Column(String(36), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    device_id = Column(String(64), nullable=True, index=True)
    token_hash = Column(String(64), nullable=False, unique=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    replaced_by_id = Column(String(36), nullable=True)

    user = relationship("User", back_populates="refresh_credentials")
