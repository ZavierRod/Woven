from __future__ import annotations

import hashlib
import hmac
import uuid
from datetime import datetime, timedelta, timezone
from typing import Callable, Optional

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from sqlalchemy.orm import Session

from app.core.config import Settings, settings
from app.deps import get_db
from app.models.user import User

security = HTTPBearer(auto_error=False)


class AppleTokenError(ValueError):
    pass


class GoogleTokenError(ValueError):
    pass


class AppleTokenVerifier:
    """Verify Apple identity-token signature and all Woven-bound claims."""

    def __init__(
        self,
        configuration: Settings = settings,
        signing_key_resolver: Callable[[str], object] | None = None,
    ):
        self.configuration = configuration
        self._signing_key_resolver = signing_key_resolver

    def verify(self, identity_token: str, raw_nonce: str) -> dict:
        if not identity_token or not raw_nonce:
            raise AppleTokenError("Apple authentication failed")
        try:
            if self._signing_key_resolver is not None:
                signing_key = self._signing_key_resolver(identity_token)
            else:
                signing_key = PyJWKClient(
                    self.configuration.APPLE_JWKS_URL,
                    cache_keys=True,
                    lifespan=3600,
                ).get_signing_key_from_jwt(identity_token).key
            payload = jwt.decode(
                identity_token,
                signing_key,
                algorithms=["RS256"],
                audience=self.configuration.APPLE_CLIENT_ID,
                issuer=self.configuration.APPLE_ISSUER,
                options={"require": ["sub", "iss", "aud", "exp", "iat", "nonce"]},
            )
        except jwt.PyJWTError as error:
            raise AppleTokenError("Apple authentication failed") from error
        except Exception as error:
            raise AppleTokenError("Apple authentication failed") from error

        expected_nonce = hashlib.sha256(raw_nonce.encode("utf-8")).hexdigest()
        supplied_nonce = str(payload.get("nonce", ""))
        if not hmac.compare_digest(expected_nonce, supplied_nonce):
            raise AppleTokenError("Apple authentication failed")
        return payload


class GoogleTokenVerifier:
    """Verify Google identity-token signature and all Woven-bound claims."""

    def __init__(
        self,
        configuration: Settings = settings,
        signing_key_resolver: Callable[[str], object] | None = None,
    ):
        self.configuration = configuration
        self._signing_key_resolver = signing_key_resolver

    def verify(self, identity_token: str) -> dict:
        if not identity_token or not self.configuration.GOOGLE_CLIENT_ID:
            raise GoogleTokenError("Google authentication failed")
        try:
            if self._signing_key_resolver is not None:
                signing_key = self._signing_key_resolver(identity_token)
            else:
                signing_key = PyJWKClient(
                    self.configuration.GOOGLE_JWKS_URL,
                    cache_keys=True,
                    lifespan=3600,
                ).get_signing_key_from_jwt(identity_token).key
            payload = jwt.decode(
                identity_token,
                signing_key,
                algorithms=["RS256"],
                audience=self.configuration.GOOGLE_CLIENT_ID,
                options={
                    "require": [
                        "sub",
                        "iss",
                        "aud",
                        "exp",
                        "iat",
                        "email",
                        "email_verified",
                    ],
                    "verify_iss": False,
                },
            )
        except jwt.PyJWTError as error:
            raise GoogleTokenError("Google authentication failed") from error
        except Exception as error:
            raise GoogleTokenError("Google authentication failed") from error

        issuer = str(payload.get("iss", ""))
        if issuer not in {"https://accounts.google.com", "accounts.google.com"}:
            raise GoogleTokenError("Google authentication failed")
        subject = payload.get("sub")
        if not isinstance(subject, str) or not subject.strip():
            raise GoogleTokenError("Google authentication failed")
        if payload.get("email_verified") is not True:
            raise GoogleTokenError("Google authentication failed")
        email = payload.get("email")
        if not isinstance(email, str) or not email.strip():
            raise GoogleTokenError("Google authentication failed")
        return payload


def create_access_token(
    data: dict,
    expires_delta: Optional[timedelta] = None,
) -> str:
    now = datetime.now(timezone.utc)
    expire = now + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    claims = data.copy()
    claims.update({"exp": expire, "iat": now, "jti": str(uuid.uuid4()), "type": "access"})
    return jwt.encode(claims, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def issue_access_token(user: User) -> str:
    return create_access_token({"sub": str(user.id), "ver": user.auth_generation})


def decode_access_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
            options={"require": ["sub", "exp", "iat", "jti", "type"]},
        )
    except jwt.PyJWTError:
        return None


async def get_current_user_id(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> int:
    payload = decode_access_token(credentials.credentials) if credentials is not None else None
    if payload is None or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        user_id = int(payload["sub"])
    except (KeyError, TypeError, ValueError) as error:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from error
    user = db.query(User).filter(User.id == user_id).first()
    if user is None or payload.get("ver") != user.auth_generation:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return user_id
