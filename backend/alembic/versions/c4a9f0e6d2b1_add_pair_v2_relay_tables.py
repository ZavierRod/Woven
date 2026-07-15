"""add Pair Vault v2 encrypted relay tables

Revision ID: c4a9f0e6d2b1
Revises: 66e08f54fd96
Create Date: 2026-07-14
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "c4a9f0e6d2b1"
down_revision: Union[str, None] = "66e08f54fd96"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "pair_devices_v2",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("agreement_public_key", sa.String(length=128), nullable=False),
        sa.Column("created_at_ms", sa.BigInteger(), nullable=False),
        sa.Column("revoked", sa.Boolean(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id"),
    )
    op.create_index("ix_pair_devices_v2_user_id", "pair_devices_v2", ["user_id"], unique=True)

    op.create_table(
        "pair_vaults_v2",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("creator_user_id", sa.Integer(), nullable=False),
        sa.Column("encrypted_metadata", sa.Text(), nullable=False),
        sa.Column("membership_version", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False),
        sa.Column("created_at_ms", sa.BigInteger(), nullable=False),
        sa.Column("updated_at_ms", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(["creator_user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_pair_vaults_v2_creator_user_id", "pair_vaults_v2", ["creator_user_id"])

    op.create_table(
        "pair_members_v2",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("vault_id", sa.String(length=64), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("joined_at_ms", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(["device_id"], ["pair_devices_v2.id"]),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["vault_id"], ["pair_vaults_v2.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("vault_id", "device_id", name="uq_pair_v2_vault_device"),
        sa.UniqueConstraint("vault_id", "user_id", name="uq_pair_v2_vault_user"),
    )
    op.create_index("ix_pair_members_v2_user_id", "pair_members_v2", ["user_id"])
    op.create_index("ix_pair_members_v2_vault_id", "pair_members_v2", ["vault_id"])

    op.create_table(
        "pair_invitations_v2",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("vault_id", sa.String(length=64), nullable=False),
        sa.Column("creator_user_id", sa.Integer(), nullable=False),
        sa.Column("creator_device_id", sa.String(length=64), nullable=False),
        sa.Column("target_user_id", sa.Integer(), nullable=False),
        sa.Column("target_device_id", sa.String(length=64), nullable=False),
        sa.Column("token_sha256", sa.String(length=64), nullable=False),
        sa.Column("encrypted_share_envelope", sa.Text(), nullable=False),
        sa.Column("membership_version", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("created_at_ms", sa.BigInteger(), nullable=False),
        sa.Column("expires_at_ms", sa.BigInteger(), nullable=False),
        sa.Column("accepted_at_ms", sa.BigInteger(), nullable=True),
        sa.ForeignKeyConstraint(["creator_device_id"], ["pair_devices_v2.id"]),
        sa.ForeignKeyConstraint(["creator_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["target_device_id"], ["pair_devices_v2.id"]),
        sa.ForeignKeyConstraint(["target_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["vault_id"], ["pair_vaults_v2.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_sha256"),
    )
    op.create_index("ix_pair_invitations_v2_target_user_id", "pair_invitations_v2", ["target_user_id"])
    op.create_index("ix_pair_invitations_v2_vault_id", "pair_invitations_v2", ["vault_id"])

    op.create_table(
        "pair_access_requests_v2",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("vault_id", sa.String(length=64), nullable=False),
        sa.Column("requester_user_id", sa.Integer(), nullable=False),
        sa.Column("requester_device_id", sa.String(length=64), nullable=False),
        sa.Column("approver_user_id", sa.Integer(), nullable=False),
        sa.Column("approver_device_id", sa.String(length=64), nullable=False),
        sa.Column("requester_ephemeral_public_key", sa.String(length=128), nullable=False),
        sa.Column("membership_version", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("encrypted_share_envelope", sa.Text(), nullable=True),
        sa.Column("created_at_ms", sa.BigInteger(), nullable=False),
        sa.Column("expires_at_ms", sa.BigInteger(), nullable=False),
        sa.Column("responded_at_ms", sa.BigInteger(), nullable=True),
        sa.Column("consumed_at_ms", sa.BigInteger(), nullable=True),
        sa.ForeignKeyConstraint(["approver_device_id"], ["pair_devices_v2.id"]),
        sa.ForeignKeyConstraint(["approver_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["requester_device_id"], ["pair_devices_v2.id"]),
        sa.ForeignKeyConstraint(["requester_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["vault_id"], ["pair_vaults_v2.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_pair_access_requests_v2_approver_user_id", "pair_access_requests_v2", ["approver_user_id"])
    op.create_index("ix_pair_access_requests_v2_requester_user_id", "pair_access_requests_v2", ["requester_user_id"])
    op.create_index("ix_pair_access_requests_v2_vault_id", "pair_access_requests_v2", ["vault_id"])

    op.create_table(
        "pair_media_v2",
        sa.Column("id", sa.String(length=64), nullable=False),
        sa.Column("vault_id", sa.String(length=64), nullable=False),
        sa.Column("uploader_user_id", sa.Integer(), nullable=False),
        sa.Column("encrypted_blob", sa.Text(), nullable=False),
        sa.Column("encrypted_metadata", sa.Text(), nullable=False),
        sa.Column("created_at_ms", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(["uploader_user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["vault_id"], ["pair_vaults_v2.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_pair_media_v2_vault_id", "pair_media_v2", ["vault_id"])


def downgrade() -> None:
    op.drop_index("ix_pair_media_v2_vault_id", table_name="pair_media_v2")
    op.drop_table("pair_media_v2")
    op.drop_index("ix_pair_access_requests_v2_vault_id", table_name="pair_access_requests_v2")
    op.drop_index("ix_pair_access_requests_v2_requester_user_id", table_name="pair_access_requests_v2")
    op.drop_index("ix_pair_access_requests_v2_approver_user_id", table_name="pair_access_requests_v2")
    op.drop_table("pair_access_requests_v2")
    op.drop_index("ix_pair_invitations_v2_vault_id", table_name="pair_invitations_v2")
    op.drop_index("ix_pair_invitations_v2_target_user_id", table_name="pair_invitations_v2")
    op.drop_table("pair_invitations_v2")
    op.drop_index("ix_pair_members_v2_vault_id", table_name="pair_members_v2")
    op.drop_index("ix_pair_members_v2_user_id", table_name="pair_members_v2")
    op.drop_table("pair_members_v2")
    op.drop_index("ix_pair_vaults_v2_creator_user_id", table_name="pair_vaults_v2")
    op.drop_table("pair_vaults_v2")
    op.drop_index("ix_pair_devices_v2_user_id", table_name="pair_devices_v2")
    op.drop_table("pair_devices_v2")
