import uuid
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum

from app.db.session import Base


class VaultType(str, enum.Enum):
    SOLO = "solo"
    PAIR = "pair"


class VaultMode(str, enum.Enum):
    NORMAL = "normal"
    STRICT = "strict"


class MemberRole(str, enum.Enum):
    OWNER = "owner"
    MEMBER = "member"


class MemberStatus(str, enum.Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    REVOKED = "revoked"


class VaultStatus(str, enum.Enum):
    ACTIVE = "ACTIVE"
    PENDING = "PENDING"


class Vault(Base):
    """
    Encrypted media container.
    
    - Solo vaults have one owner
    - Pair vaults have owner + one member (max 2 people)
    """
    __tablename__ = "vaults"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name = Column(String, nullable=False)
    type = Column(SQLEnum(VaultType), default=VaultType.SOLO, nullable=False)
    mode = Column(SQLEnum(VaultMode), default=VaultMode.NORMAL, nullable=False)
    status = Column(SQLEnum(VaultStatus), default=VaultStatus.ACTIVE, nullable=False)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    last_accessed_at = Column(DateTime(timezone=True), nullable=True)
    
    # Relationships
    owner = relationship("User", back_populates="owned_vaults")
    members = relationship("VaultMember", back_populates="vault", cascade="all, delete-orphan")
    media = relationship("VaultMedia", back_populates="vault", cascade="all, delete-orphan")
    access_requests = relationship("AccessRequest", back_populates="vault", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<Vault(id={self.id}, name={self.name}, type={self.type})>"


class VaultMember(Base):
    """
    Vault membership - links users to vaults.
    
    For pair vaults:
    - Owner is added automatically with role=OWNER, status=ACCEPTED
    - Partner is added with role=MEMBER, status=PENDING until they accept
    """
    __tablename__ = "vault_members"

    id = Column(Integer, primary_key=True, index=True)
    vault_id = Column(UUID(as_uuid=True), ForeignKey("vaults.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    role = Column(SQLEnum(MemberRole), default=MemberRole.MEMBER, nullable=False)
    status = Column(SQLEnum(MemberStatus), default=MemberStatus.PENDING, nullable=False)
    
    # For strict mode: encrypted key share (future)
    key_share = Column(String, nullable=True)
    
    # Timestamps
    joined_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationships
    vault = relationship("Vault", back_populates="members")
    user = relationship("User", back_populates="vault_memberships")

    def __repr__(self):
        return f"<VaultMember(vault_id={self.vault_id}, user_id={self.user_id}, role={self.role})>"


