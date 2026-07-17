"""Persistent relay records for the development Pair Vault v2 protocol.

All user content and key material stored here is already encrypted by an iOS
client. Account, device, membership, timing, and object identifiers remain
visible to the relay and are intentionally called out in the threat model.
"""

from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.db.session import Base


class PairDeviceV2(Base):
    __tablename__ = "pair_devices_v2"
    __table_args__ = (
        UniqueConstraint("user_id", name="pair_devices_v2_user_id_key"),
        Index("ix_pair_devices_v2_user_id", "user_id", unique=True),
    )

    id = Column(String(64), primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    agreement_public_key = Column(String(128), nullable=False)
    signing_public_key = Column(String(128), nullable=False)
    created_at_ms = Column(BigInteger, nullable=False)
    revoked = Column(Boolean, nullable=False, default=False)


class PairVaultV2(Base):
    __tablename__ = "pair_vaults_v2"

    id = Column(String(64), primary_key=True)
    creator_user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    encrypted_metadata = Column(Text, nullable=False)
    membership_version = Column(Integer, nullable=False, default=1)
    status = Column(String(24), nullable=False, default="pending")
    created_at_ms = Column(BigInteger, nullable=False)
    updated_at_ms = Column(BigInteger, nullable=False)

    members = relationship("PairMemberV2", cascade="all, delete-orphan", back_populates="vault")
    invitations = relationship("PairInvitationV2", cascade="all, delete-orphan", back_populates="vault")
    access_requests = relationship("PairAccessRequestV2", cascade="all, delete-orphan", back_populates="vault")
    media = relationship("PairMediaV2", cascade="all, delete-orphan", back_populates="vault")


class PairMemberV2(Base):
    __tablename__ = "pair_members_v2"
    __table_args__ = (
        UniqueConstraint("vault_id", "user_id", name="uq_pair_v2_vault_user"),
        UniqueConstraint("vault_id", "device_id", name="uq_pair_v2_vault_device"),
    )

    id = Column(Integer, primary_key=True)
    vault_id = Column(String(64), ForeignKey("pair_vaults_v2.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    device_id = Column(String(64), ForeignKey("pair_devices_v2.id"), nullable=False)
    role = Column(String(16), nullable=False)
    status = Column(String(16), nullable=False, default="active")
    joined_at_ms = Column(BigInteger, nullable=False)

    vault = relationship("PairVaultV2", back_populates="members")


class PairInvitationV2(Base):
    __tablename__ = "pair_invitations_v2"

    id = Column(String(64), primary_key=True)
    vault_id = Column(String(64), ForeignKey("pair_vaults_v2.id", ondelete="CASCADE"), nullable=False, index=True)
    creator_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    creator_device_id = Column(String(64), ForeignKey("pair_devices_v2.id"), nullable=False)
    target_user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    target_device_id = Column(String(64), ForeignKey("pair_devices_v2.id"), nullable=False)
    token_sha256 = Column(String(64), nullable=False, unique=True)
    encrypted_share_envelope = Column(Text, nullable=False)
    membership_version = Column(Integer, nullable=False)
    status = Column(String(20), nullable=False, default="pending")
    created_at_ms = Column(BigInteger, nullable=False)
    expires_at_ms = Column(BigInteger, nullable=False)
    accepted_at_ms = Column(BigInteger, nullable=True)

    vault = relationship("PairVaultV2", back_populates="invitations")


class PairAccessRequestV2(Base):
    __tablename__ = "pair_access_requests_v2"

    id = Column(String(64), primary_key=True)
    vault_id = Column(String(64), ForeignKey("pair_vaults_v2.id", ondelete="CASCADE"), nullable=False, index=True)
    requester_user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    requester_device_id = Column(String(64), ForeignKey("pair_devices_v2.id"), nullable=False)
    approver_user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    approver_device_id = Column(String(64), ForeignKey("pair_devices_v2.id"), nullable=False)
    requester_ephemeral_public_key = Column(String(128), nullable=False)
    membership_version = Column(Integer, nullable=False)
    status = Column(String(20), nullable=False, default="pending")
    encrypted_share_envelope = Column(Text, nullable=True)
    created_at_ms = Column(BigInteger, nullable=False)
    expires_at_ms = Column(BigInteger, nullable=False)
    responded_at_ms = Column(BigInteger, nullable=True)
    consumed_at_ms = Column(BigInteger, nullable=True)

    vault = relationship("PairVaultV2", back_populates="access_requests")


class PairMediaV2(Base):
    __tablename__ = "pair_media_v2"

    id = Column(String(64), primary_key=True)
    vault_id = Column(String(64), ForeignKey("pair_vaults_v2.id", ondelete="CASCADE"), nullable=False, index=True)
    uploader_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    # Legacy rows may contain ciphertext in the database. New writes use the
    # opaque storage adapter and leave this column null.
    encrypted_blob = Column(Text, nullable=True)
    storage_key = Column(String(96), nullable=True, unique=True)
    encrypted_metadata = Column(Text, nullable=False)
    created_at_ms = Column(BigInteger, nullable=False)

    vault = relationship("PairVaultV2", back_populates="media")


class PairDeviceRequestNonceV2(Base):
    __tablename__ = "pair_device_request_nonces_v2"
    __table_args__ = (
        UniqueConstraint("device_id", "nonce", name="uq_pair_v2_device_nonce"),
        UniqueConstraint("device_id", "request_id", name="uq_pair_v2_device_request_id"),
    )

    id = Column(Integer, primary_key=True)
    device_id = Column(String(64), ForeignKey("pair_devices_v2.id", ondelete="CASCADE"), nullable=False, index=True)
    nonce = Column(String(128), nullable=False)
    request_id = Column(String(64), nullable=False)
    timestamp_ms = Column(BigInteger, nullable=False)
    created_at_ms = Column(BigInteger, nullable=False)
