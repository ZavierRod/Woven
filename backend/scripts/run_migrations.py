"""Run the complete fail-closed staging migration gate as one provider command."""

from __future__ import annotations

from alembic import command
from alembic.config import Config

from validate_staging_config import main as validate_staging_config
from verify_migration import main as verify_migration


def main() -> None:
    validate_staging_config()
    configuration = Config("alembic.ini")
    command.upgrade(configuration, "head")
    verify_migration()
    command.check(configuration)
    print("staging migration gate passed")


if __name__ == "__main__":
    main()
