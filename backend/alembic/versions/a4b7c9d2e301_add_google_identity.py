"""add Google federated identity

Revision ID: a4b7c9d2e301
Revises: d7a4c10b8e21
Create Date: 2026-07-23
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a4b7c9d2e301"
down_revision: Union[str, None] = "d7a4c10b8e21"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("google_user_id", sa.String(), nullable=True))
    op.create_index(
        op.f("ix_users_google_user_id"),
        "users",
        ["google_user_id"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_users_google_user_id"), table_name="users")
    op.drop_column("users", "google_user_id")
