"""
Storage service for handling media file uploads and downloads.

For MVP, uses local filesystem storage. Can be extended to S3/Cloud Storage later.
"""
import os
import uuid
from pathlib import Path
from typing import Optional
from datetime import datetime, timedelta
from urllib.parse import quote

from app.core.config import settings


class StorageService:
    """Service for managing media file storage."""

    def __init__(self):
        self.base_path = Path(settings.MEDIA_STORAGE_PATH)
        self.base_path.mkdir(parents=True, exist_ok=True)

    def generate_storage_key(self, vault_id: str, media_id: str, file_name: str) -> str:
        """Generate a unique storage key for a media file."""
        # Use vault_id/media_id/filename structure
        # Sanitize filename
        safe_filename = quote(file_name, safe='')
        return f"{vault_id}/{media_id}/{safe_filename}"

    def get_file_path(self, storage_key: str) -> Path:
        """Get the full file system path for a storage key."""
        return self.base_path / storage_key

    def save_file(self, storage_key: str, file_content: bytes) -> None:
        """Save file content to storage."""
        file_path = self.get_file_path(storage_key)
        file_path.parent.mkdir(parents=True, exist_ok=True)

        with open(file_path, 'wb') as f:
            f.write(file_content)

    def get_file(self, storage_key: str) -> Optional[bytes]:
        """Retrieve file content from storage."""
        file_path = self.get_file_path(storage_key)

        if not file_path.exists():
            return None

        with open(file_path, 'rb') as f:
            return f.read()

    def delete_file(self, storage_key: str) -> bool:
        """Delete a file from storage."""
        file_path = self.get_file_path(storage_key)

        if not file_path.exists():
            return False

        file_path.unlink()

        # Clean up empty directories
        try:
            file_path.parent.rmdir()
            file_path.parent.parent.rmdir()
        except OSError:
            pass  # Directory not empty, that's fine

        return True

    def generate_upload_url(self, storage_key: str) -> tuple[str, int]:
        """
        Generate a temporary upload URL.

        For local filesystem, this is a simple POST endpoint.
        Returns: (upload_url, expiry_seconds)
        """
        # In production with S3, this would generate a presigned POST URL
        # For now, return the storage key and expiry
        upload_url = f"/api/media/upload/{storage_key}"
        return upload_url, settings.MEDIA_UPLOAD_URL_EXPIRY

    def generate_view_url(self, storage_key: str) -> tuple[str, int]:
        """
        Generate a temporary view URL for reading media.

        For local filesystem, this is a GET endpoint.
        Returns: (view_url, expiry_seconds)
        """
        # In production with S3, this would generate a presigned GET URL
        # For now, return the storage key and expiry
        view_url = f"/api/media/view/{storage_key}"
        return view_url, settings.MEDIA_VIEW_URL_EXPIRY


# Singleton instance
storage_service = StorageService()

