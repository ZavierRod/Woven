import os
from dotenv import load_dotenv
from pydantic import model_validator
from pydantic_settings import BaseSettings

load_dotenv()


class Settings(BaseSettings):
    # App
    APP_NAME: str = "Woven API"
    DEBUG: bool = False

    # Database
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql://woven_user:woven_password@localhost:5433/woven"
    )

    # JWT
    SECRET_KEY: str = os.getenv("SECRET_KEY", "")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    # Storage (local filesystem for MVP, can switch to S3 later)
    MEDIA_STORAGE_PATH: str = os.getenv("MEDIA_STORAGE_PATH", "./storage/media")
    MEDIA_UPLOAD_URL_EXPIRY: int = 3600  # 1 hour
    MEDIA_VIEW_URL_EXPIRY: int = 600  # 10 minutes (shorter for view-only)

    # APNs
    APNS_TEAM_ID: str | None = None
    APNS_KEY_ID: str | None = None
    APNS_KEY_PATH: str | None = None
    APNS_BUNDLE_ID: str | None = None
    APNS_ENVIRONMENT: str = "sandbox"

    @model_validator(mode="after")
    def validate_security_configuration(self):
        if not self.DEBUG and len(self.SECRET_KEY) < 32:
            raise ValueError("SECRET_KEY must contain at least 32 characters when DEBUG is false")
        return self

    class Config:
        env_file = ".env"


settings = Settings()
