"""Opaque ciphertext storage adapters for local development and object storage."""

from __future__ import annotations

import uuid
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional

from app.core.config import StorageBackend, settings


class CiphertextStorage(ABC):
    @staticmethod
    def generate_storage_key(*_ignored: str) -> str:
        # No account, vault, media, or user-supplied filename is disclosed in keys.
        return f"objects/{uuid.uuid4().hex}"

    @abstractmethod
    def save_file(self, storage_key: str, file_content: bytes) -> None: ...

    @abstractmethod
    def get_file(self, storage_key: str) -> Optional[bytes]: ...

    @abstractmethod
    def delete_file(self, storage_key: str) -> bool: ...

    def generate_upload_url(self, _storage_key: str) -> tuple[str, int]:
        raise RuntimeError("Direct object upload URLs are disabled; upload through the authenticated API")

    def generate_view_url(self, storage_key: str) -> tuple[str, int]:
        # This is an authenticated application route, never a public object URL.
        return f"/media/object/{storage_key.rsplit('/', 1)[-1]}", settings.MEDIA_VIEW_URL_EXPIRY


class LocalCiphertextStorage(CiphertextStorage):
    def __init__(self, base_path: str):
        self.base_path = Path(base_path).resolve()
        self.base_path.mkdir(parents=True, exist_ok=True)

    def get_file_path(self, storage_key: str) -> Path:
        candidate = (self.base_path / storage_key).resolve()
        if self.base_path not in candidate.parents:
            raise ValueError("Invalid opaque storage key")
        return candidate

    def save_file(self, storage_key: str, file_content: bytes) -> None:
        file_path = self.get_file_path(storage_key)
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_bytes(file_content)

    def get_file(self, storage_key: str) -> Optional[bytes]:
        file_path = self.get_file_path(storage_key)
        return file_path.read_bytes() if file_path.is_file() else None

    def delete_file(self, storage_key: str) -> bool:
        file_path = self.get_file_path(storage_key)
        if not file_path.is_file():
            return False
        file_path.unlink()
        return True


class ObjectCiphertextStorage(CiphertextStorage):
    def __init__(self):
        try:
            import boto3
        except ImportError as error:
            raise RuntimeError("boto3 is required for object storage") from error
        self.bucket = settings.OBJECT_STORAGE_BUCKET
        self.client = boto3.client(
            "s3",
            endpoint_url=settings.OBJECT_STORAGE_ENDPOINT,
            region_name=settings.OBJECT_STORAGE_REGION or None,
            aws_access_key_id=settings.OBJECT_STORAGE_ACCESS_KEY,
            aws_secret_access_key=settings.OBJECT_STORAGE_SECRET_KEY,
        )

    def save_file(self, storage_key: str, file_content: bytes) -> None:
        self.client.put_object(
            Bucket=self.bucket,
            Key=storage_key,
            Body=file_content,
            ContentType="application/octet-stream",
            ServerSideEncryption="AES256",
        )

    def get_file(self, storage_key: str) -> Optional[bytes]:
        try:
            return self.client.get_object(Bucket=self.bucket, Key=storage_key)["Body"].read()
        except self.client.exceptions.NoSuchKey:
            return None

    def delete_file(self, storage_key: str) -> bool:
        self.client.delete_object(Bucket=self.bucket, Key=storage_key)
        return True


storage_service: CiphertextStorage
if settings.STORAGE_BACKEND == StorageBackend.OBJECT:
    storage_service = ObjectCiphertextStorage()
else:
    storage_service = LocalCiphertextStorage(settings.MEDIA_STORAGE_PATH)
