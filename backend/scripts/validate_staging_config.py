"""Validate staging environment variables without printing their values."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.config import AppEnvironment, Settings  # noqa: E402


def main() -> None:
    configuration = Settings()
    if configuration.APP_ENV != AppEnvironment.STAGING:
        raise SystemExit("APP_ENV must be staging")
    print("staging configuration valid")
    print("validated fields: " + ",".join(sorted(Settings.model_fields)))


if __name__ == "__main__":
    main()
