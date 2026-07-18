from __future__ import annotations

from enum import Enum
from typing import Literal, Optional
from urllib.parse import urlparse

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class AppEnvironment(str, Enum):
    LOCAL = "local"
    TEST = "test"
    STAGING = "staging"
    PRODUCTION = "production"


class StorageBackend(str, Enum):
    LOCAL = "local"
    OBJECT = "object"


class Settings(BaseSettings):
    """Fail-closed environment configuration with safe diagnostics."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    APP_NAME: str = "Woven API"
    APP_ENV: AppEnvironment = AppEnvironment.PRODUCTION
    DEBUG: bool = False
    PUBLIC_BASE_URL: str = ""
    DATABASE_URL: str = ""

    SECRET_KEY: str = ""
    REFRESH_TOKEN_PEPPER: str = ""
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=15, ge=5, le=60)
    REFRESH_TOKEN_EXPIRE_DAYS: int = Field(default=30, ge=1, le=90)

    APPLE_CLIENT_ID: str = ""
    APPLE_ISSUER: str = "https://appleid.apple.com"
    APPLE_JWKS_URL: str = "https://appleid.apple.com/auth/keys"

    CORS_ORIGINS: str = ""
    TRUSTED_HOSTS: str = ""
    REQUEST_TIMEOUT_SECONDS: int = Field(default=30, ge=5, le=120)
    MAX_REQUEST_BYTES: int = Field(default=21 * 1024 * 1024, ge=1024)
    MAX_MEDIA_BYTES: int = Field(default=20 * 1024 * 1024, ge=1024)
    MAX_METADATA_BYTES: int = Field(default=32 * 1024, ge=256)
    RATE_LIMIT_AUTH_PER_MINUTE: int = Field(default=10, ge=1)
    RATE_LIMIT_PAIR_PER_MINUTE: int = Field(default=120, ge=1)

    STORAGE_BACKEND: StorageBackend = StorageBackend.LOCAL
    MEDIA_STORAGE_PATH: str = "./storage/media"
    OBJECT_STORAGE_ENDPOINT: str = ""
    OBJECT_STORAGE_BUCKET: str = ""
    OBJECT_STORAGE_REGION: str = ""
    OBJECT_STORAGE_ACCESS_KEY: str = ""
    OBJECT_STORAGE_SECRET_KEY: str = ""
    OBJECT_STORAGE_ADDRESSING_STYLE: Literal["auto", "virtual", "path"] = "auto"
    OBJECT_STORAGE_SERVER_SIDE_ENCRYPTION: str = ""
    MEDIA_UPLOAD_URL_EXPIRY: int = Field(default=300, ge=30, le=900)
    MEDIA_VIEW_URL_EXPIRY: int = Field(default=300, ge=30, le=900)

    ENFORCE_DEVICE_SIGNATURES: bool = False
    DEVICE_SIGNATURE_CLOCK_SKEW_SECONDS: int = Field(default=120, ge=30, le=300)

    APNS_TEAM_ID: Optional[str] = None
    APNS_KEY_ID: Optional[str] = None
    APNS_KEY_PATH: Optional[str] = None
    APNS_BUNDLE_ID: Optional[str] = None
    APNS_ENVIRONMENT: str = "sandbox"

    @property
    def is_local(self) -> bool:
        return self.APP_ENV == AppEnvironment.LOCAL

    @property
    def is_test(self) -> bool:
        return self.APP_ENV == AppEnvironment.TEST

    @property
    def is_remote(self) -> bool:
        return self.APP_ENV in {AppEnvironment.STAGING, AppEnvironment.PRODUCTION}

    @property
    def development_auth_enabled(self) -> bool:
        return self.APP_ENV in {AppEnvironment.LOCAL, AppEnvironment.TEST}

    @property
    def cors_origins(self) -> list[str]:
        return [value.strip() for value in self.CORS_ORIGINS.split(",") if value.strip()]

    @property
    def trusted_hosts(self) -> list[str]:
        return [value.strip() for value in self.TRUSTED_HOSTS.split(",") if value.strip()]

    def safe_summary(self) -> dict[str, str | bool]:
        """Return operational fields only; credentials are deliberately absent."""
        return {
            "environment": self.APP_ENV.value,
            "debug": self.DEBUG,
            "database_engine": urlparse(self.DATABASE_URL).scheme,
            "storage_backend": self.STORAGE_BACKEND.value,
            "device_signatures": self.ENFORCE_DEVICE_SIGNATURES,
        }

    @model_validator(mode="after")
    def validate_security_configuration(self) -> "Settings":
        errors: list[str] = []
        public_url = urlparse(self.PUBLIC_BASE_URL)
        database_scheme = urlparse(self.DATABASE_URL).scheme

        if len(self.SECRET_KEY) < 32:
            errors.append("SECRET_KEY must contain at least 32 characters")
        if len(self.REFRESH_TOKEN_PEPPER) < 32:
            errors.append("REFRESH_TOKEN_PEPPER must contain at least 32 characters")
        if self.SECRET_KEY and self.SECRET_KEY == self.REFRESH_TOKEN_PEPPER:
            errors.append("SECRET_KEY and REFRESH_TOKEN_PEPPER must be independent values")
        if not self.DATABASE_URL:
            errors.append("DATABASE_URL is required")

        if self.is_remote:
            if self.DEBUG:
                errors.append("DEBUG must be false in staging and production")
            if public_url.scheme != "https" or not public_url.netloc:
                errors.append("PUBLIC_BASE_URL must be an absolute HTTPS URL in staging and production")
            if public_url.hostname in {"localhost", "127.0.0.1", "::1"}:
                errors.append("PUBLIC_BASE_URL cannot use localhost in staging or production")
            if not database_scheme.startswith("postgresql"):
                errors.append("DATABASE_URL must use PostgreSQL in staging and production")
            if not self.APPLE_CLIENT_ID:
                errors.append("APPLE_CLIENT_ID is required in staging and production")
            if self.APPLE_ISSUER != "https://appleid.apple.com":
                errors.append("APPLE_ISSUER must use Apple's official HTTPS issuer")
            if self.APPLE_JWKS_URL != "https://appleid.apple.com/auth/keys":
                errors.append("APPLE_JWKS_URL must use Apple's official HTTPS key endpoint")
            if not self.ENFORCE_DEVICE_SIGNATURES:
                errors.append("ENFORCE_DEVICE_SIGNATURES must be true in staging and production")
            if not self.trusted_hosts:
                errors.append("TRUSTED_HOSTS is required in staging and production")
            if "*" in self.trusted_hosts:
                errors.append("TRUSTED_HOSTS cannot contain '*' in staging or production")
            if public_url.hostname and public_url.hostname not in self.trusted_hosts:
                errors.append("TRUSTED_HOSTS must include the PUBLIC_BASE_URL hostname")
            if "*" in self.cors_origins:
                errors.append("CORS_ORIGINS cannot contain '*' in staging or production")
            if self.STORAGE_BACKEND != StorageBackend.OBJECT:
                errors.append("STORAGE_BACKEND must be 'object' in staging and production")
            for name, value in {
                "OBJECT_STORAGE_ENDPOINT": self.OBJECT_STORAGE_ENDPOINT,
                "OBJECT_STORAGE_BUCKET": self.OBJECT_STORAGE_BUCKET,
                "OBJECT_STORAGE_ACCESS_KEY": self.OBJECT_STORAGE_ACCESS_KEY,
                "OBJECT_STORAGE_SECRET_KEY": self.OBJECT_STORAGE_SECRET_KEY,
            }.items():
                if not value:
                    errors.append(f"{name} is required for remote object storage")
            object_url = urlparse(self.OBJECT_STORAGE_ENDPOINT)
            if object_url.scheme != "https" or not object_url.netloc:
                errors.append("OBJECT_STORAGE_ENDPOINT must be an absolute HTTPS URL")

        if self.is_local:
            if public_url.scheme not in {"http", "https"} or not public_url.netloc:
                errors.append("PUBLIC_BASE_URL must be an absolute HTTP(S) URL for local development")
            if database_scheme not in {"sqlite", "postgresql", "postgresql+psycopg2"}:
                errors.append("local DATABASE_URL must use SQLite or PostgreSQL")

        if self.is_test and not database_scheme.startswith("sqlite"):
            errors.append("test DATABASE_URL must use SQLite")

        if errors:
            raise ValueError("Invalid Woven configuration: " + "; ".join(errors))
        return self


settings = Settings()
