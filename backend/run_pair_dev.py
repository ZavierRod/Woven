"""Run a persistent, disposable SQLite Pair Vault v2 development relay."""

import os

os.environ.setdefault("DATABASE_URL", "sqlite:///./woven-pair-dev.db")
os.environ.setdefault("DEBUG", "true")
os.environ.setdefault("SECRET_KEY", "woven-pair-local-development-only-key")

import uvicorn

from app.db import base as _models  # noqa: F401
from app.db.session import Base, engine
from app.main import app


if __name__ == "__main__":
    Base.metadata.create_all(bind=engine)
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
