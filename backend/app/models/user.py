from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from app.db.session import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    
    # Email/Password Auth (primary method)
    username = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    
    # Profile
    full_name = Column(String, nullable=True)
    profile_picture_url = Column(String, nullable=True)
    invite_code = Column(String, unique=True, index=True, nullable=True)
    
    # Federated identities. Provider subjects, not email addresses, identify accounts.
    apple_user_id = Column(String, unique=True, index=True, nullable=True)
    google_user_id = Column(String, unique=True, index=True, nullable=True)
    auth_generation = Column(Integer, nullable=False, default=0)
    
    # Encryption
    public_key = Column(String, nullable=True)
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    owned_vaults = relationship("Vault", back_populates="owner")
    vault_memberships = relationship("VaultMember", back_populates="user")
    devices = relationship("DeviceToken", back_populates="user", cascade="all, delete-orphan")
    refresh_credentials = relationship("RefreshCredential", cascade="all, delete-orphan", back_populates="user")

    def __repr__(self):
        return f"<User(id={self.id}, username={self.username})>"
