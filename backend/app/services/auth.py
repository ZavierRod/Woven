from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import issue_access_token
from app.models.auth import RefreshCredential
from app.models.user import User


class RefreshCredentialError(ValueError):
    pass


@dataclass(frozen=True)
class IssuedSession:
    access_token: str
    refresh_token: str


def _hash_refresh_secret(secret: str) -> str:
    return hmac.new(
        settings.REFRESH_TOKEN_PEPPER.encode("utf-8"),
        secret.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def _new_refresh(user: User, family_id: str | None = None, device_id: str | None = None) -> tuple[RefreshCredential, str]:
    credential_id = str(uuid.uuid4())
    secret = secrets.token_urlsafe(48)
    record = RefreshCredential(
        id=credential_id,
        family_id=family_id or str(uuid.uuid4()),
        user_id=user.id,
        device_id=device_id,
        token_hash=_hash_refresh_secret(secret),
        expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    return record, f"{credential_id}.{secret}"


def issue_session(db: Session, user: User, device_id: str | None = None) -> IssuedSession:
    refresh, raw_refresh = _new_refresh(user, device_id=device_id)
    db.add(refresh)
    db.commit()
    return IssuedSession(issue_access_token(user), raw_refresh)


def _parse_refresh(raw_token: str) -> tuple[str, str]:
    try:
        credential_id, secret = raw_token.split(".", 1)
        uuid.UUID(credential_id)
    except (ValueError, AttributeError) as error:
        raise RefreshCredentialError("Invalid refresh credential") from error
    if len(secret) < 32:
        raise RefreshCredentialError("Invalid refresh credential")
    return credential_id, secret


def rotate_refresh(db: Session, raw_token: str) -> IssuedSession:
    credential_id, secret = _parse_refresh(raw_token)
    record = db.query(RefreshCredential).filter(RefreshCredential.id == credential_id).with_for_update().first()
    if record is None:
        raise RefreshCredentialError("Invalid refresh credential")
    now = datetime.now(timezone.utc)
    if record.revoked_at is not None:
        if record.replaced_by_id is not None:
            db.query(RefreshCredential).filter(
                RefreshCredential.family_id == record.family_id,
                RefreshCredential.revoked_at.is_(None),
            ).update({RefreshCredential.revoked_at: now}, synchronize_session=False)
            user = db.query(User).filter(User.id == record.user_id).with_for_update().one()
            user.auth_generation += 1
            db.commit()
        raise RefreshCredentialError("Invalid refresh credential")
    expires_at = record.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at <= now or not hmac.compare_digest(record.token_hash, _hash_refresh_secret(secret)):
        raise RefreshCredentialError("Invalid refresh credential")

    user = db.query(User).filter(User.id == record.user_id).one()
    replacement, raw_replacement = _new_refresh(user, family_id=record.family_id, device_id=record.device_id)
    record.revoked_at = now
    record.last_used_at = now
    record.replaced_by_id = replacement.id
    db.add(replacement)
    db.commit()
    return IssuedSession(issue_access_token(user), raw_replacement)


def revoke_refresh(db: Session, raw_token: str) -> None:
    credential_id, secret = _parse_refresh(raw_token)
    record = db.query(RefreshCredential).filter(RefreshCredential.id == credential_id).with_for_update().first()
    if record is None or not hmac.compare_digest(record.token_hash, _hash_refresh_secret(secret)):
        return
    if record.revoked_at is None:
        record.revoked_at = datetime.now(timezone.utc)
        db.commit()
