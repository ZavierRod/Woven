"""add rotating auth and signed device request security

Revision ID: d7a4c10b8e21
Revises: c4a9f0e6d2b1
Create Date: 2026-07-17
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d7a4c10b8e21"
down_revision: Union[str, None] = "c4a9f0e6d2b1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("auth_generation", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "pair_devices_v2",
        sa.Column("signing_public_key", sa.String(length=128), nullable=True),
    )
    # Existing local devices must re-enrol before remote signature enforcement.
    # Copying the 32-byte value keeps migration atomic without exposing secrets.
    op.execute("UPDATE pair_devices_v2 SET signing_public_key = agreement_public_key")
    with op.batch_alter_table("pair_devices_v2") as batch_op:
        batch_op.alter_column("signing_public_key", existing_type=sa.String(length=128), nullable=False)
    with op.batch_alter_table("pair_media_v2") as batch_op:
        batch_op.alter_column("encrypted_blob", existing_type=sa.Text(), nullable=True)
        batch_op.add_column(sa.Column("storage_key", sa.String(length=96), nullable=True))
        batch_op.create_unique_constraint("uq_pair_media_v2_storage_key", ["storage_key"])

    op.create_table(
        "refresh_credentials",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("family_id", sa.String(length=36), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=True),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("replaced_by_id", sa.String(length=36), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index("ix_refresh_credentials_family_id", "refresh_credentials", ["family_id"])
    op.create_index("ix_refresh_credentials_user_id", "refresh_credentials", ["user_id"])
    op.create_index("ix_refresh_credentials_device_id", "refresh_credentials", ["device_id"])

    op.create_table(
        "pair_device_request_nonces_v2",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False),
        sa.Column("nonce", sa.String(length=128), nullable=False),
        sa.Column("request_id", sa.String(length=64), nullable=False),
        sa.Column("timestamp_ms", sa.BigInteger(), nullable=False),
        sa.Column("created_at_ms", sa.BigInteger(), nullable=False),
        sa.ForeignKeyConstraint(["device_id"], ["pair_devices_v2.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("device_id", "nonce", name="uq_pair_v2_device_nonce"),
        sa.UniqueConstraint("device_id", "request_id", name="uq_pair_v2_device_request_id"),
    )
    op.create_index(
        "ix_pair_device_request_nonces_v2_device_id",
        "pair_device_request_nonces_v2",
        ["device_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_pair_device_request_nonces_v2_device_id", table_name="pair_device_request_nonces_v2")
    op.drop_table("pair_device_request_nonces_v2")
    op.drop_index("ix_refresh_credentials_device_id", table_name="refresh_credentials")
    op.drop_index("ix_refresh_credentials_user_id", table_name="refresh_credentials")
    op.drop_index("ix_refresh_credentials_family_id", table_name="refresh_credentials")
    op.drop_table("refresh_credentials")
    with op.batch_alter_table("pair_devices_v2") as batch_op:
        batch_op.drop_column("signing_public_key")
    with op.batch_alter_table("pair_media_v2") as batch_op:
        batch_op.drop_constraint("uq_pair_media_v2_storage_key", type_="unique")
        batch_op.drop_column("storage_key")
        batch_op.alter_column("encrypted_blob", existing_type=sa.Text(), nullable=False)
    op.drop_column("users", "auth_generation")
