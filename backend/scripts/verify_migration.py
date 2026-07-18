"""Verify the database is exactly at the repository's single Alembic head."""

from __future__ import annotations

import sys
from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import text

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.db.session import engine  # noqa: E402


def main() -> None:
    repository_head = ScriptDirectory.from_config(Config("alembic.ini")).get_current_head()
    with engine.connect() as connection:
        database_head = connection.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
    if database_head != repository_head:
        raise SystemExit("database revision does not match repository head")
    print(f"database migration verified at {database_head}")


if __name__ == "__main__":
    main()
