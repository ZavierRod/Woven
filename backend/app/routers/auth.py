import hashlib
import secrets

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    AppleTokenError,
    AppleTokenVerifier,
    GoogleTokenError,
    GoogleTokenVerifier,
    decode_access_token,
    issue_access_token,
)
from app.crud.user import hash_password, user_crud
from app.deps import get_db
from app.models.user import User
from app.schemas.auth import (
    AppleSignInRequest,
    AuthResponse,
    GoogleSignInRequest,
    LoginRequest,
    LogoutRequest,
    RefreshRequest,
    SessionResponse,
    SignUpRequest,
)
from app.services.auth import (
    RefreshCredentialError,
    issue_session,
    revoke_refresh,
    rotate_refresh,
)

router = APIRouter(prefix="/auth", tags=["Authentication"])


def get_apple_verifier() -> AppleTokenVerifier:
    return AppleTokenVerifier()


def get_google_verifier() -> GoogleTokenVerifier:
    if not settings.GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=404, detail="Not found")
    return GoogleTokenVerifier()


def _auth_response(user: User, access_token: str) -> AuthResponse:
    return AuthResponse(
        access_token=access_token,
        user_id=user.id,
        username=user.username,
        email=user.email,
        full_name=user.full_name,
        invite_code=user.invite_code,
    )


def _session_response(user: User, access_token: str, refresh_token: str) -> SessionResponse:
    base = _auth_response(user, access_token)
    return SessionResponse(**base.model_dump(), refresh_token=refresh_token)


def _require_development_auth() -> None:
    if not settings.development_auth_enabled:
        raise HTTPException(status_code=404, detail="Not found")


@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def sign_up(request: SignUpRequest, db: Session = Depends(get_db)):
    _require_development_auth()
    if user_crud.email_exists(db, request.email):
        raise HTTPException(status_code=400, detail="Email already registered")
    if user_crud.username_exists(db, request.username):
        raise HTTPException(status_code=400, detail="Username already taken")
    user = user_crud.create(db, request)
    return _auth_response(user, issue_access_token(user))


@router.post("/login", response_model=AuthResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    _require_development_auth()
    user = user_crud.authenticate(db, request.identifier, request.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid email/username or password")
    return _auth_response(user, issue_access_token(user))


@router.post("/apple", response_model=SessionResponse)
def sign_in_with_apple(
    request: AppleSignInRequest,
    db: Session = Depends(get_db),
    verifier: AppleTokenVerifier = Depends(get_apple_verifier),
):
    try:
        apple_claims = verifier.verify(request.identity_token, request.nonce)
    except AppleTokenError as error:
        raise HTTPException(status_code=401, detail="Apple authentication failed") from error

    subject = str(apple_claims["sub"])
    user = user_crud.get_by_apple_id(db, subject)
    if user is None:
        digest = hashlib.sha256(subject.encode("utf-8")).hexdigest()[:20]
        username = f"apple_{digest}"
        claimed_email = str(
            apple_claims.get("email") or f"{username}@privaterelay.invalid"
        ).strip().lower()
        # Provider subjects remain distinct unless an already-authenticated
        # Woven user explicitly links them in a future account-linking flow.
        email = (
            f"{username}@identity.invalid"
            if user_crud.email_exists(db, claimed_email)
            else claimed_email
        )
        user = User(
            username=username,
            email=email,
            password_hash=hash_password(secrets.token_urlsafe(32)),
            full_name=request.full_name,
            invite_code=secrets.token_hex(4).upper(),
            apple_user_id=subject,
            auth_generation=0,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    session = issue_session(db, user, device_id=request.device_id)
    return _session_response(user, session.access_token, session.refresh_token)


@router.post("/google", response_model=SessionResponse)
def sign_in_with_google(
    request: GoogleSignInRequest,
    db: Session = Depends(get_db),
    verifier: GoogleTokenVerifier = Depends(get_google_verifier),
):
    try:
        google_claims = verifier.verify(request.id_token)
    except GoogleTokenError as error:
        raise HTTPException(status_code=401, detail="Google authentication failed") from error

    subject = str(google_claims["sub"])
    user = user_crud.get_by_google_id(db, subject)
    if user is None:
        digest = hashlib.sha256(subject.encode("utf-8")).hexdigest()[:20]
        username = f"google_{digest}"
        verified_email = str(google_claims["email"]).strip().lower()
        # Do not automatically link providers by email. A verified address can
        # back a distinct Apple identity, and silent linking would collapse the
        # two accounts without proving control of the existing Woven session.
        email = (
            f"{username}@identity.invalid"
            if user_crud.email_exists(db, verified_email)
            else verified_email
        )
        full_name = google_claims.get("name")
        user = User(
            username=username,
            email=email,
            password_hash=hash_password(secrets.token_urlsafe(32)),
            full_name=str(full_name) if isinstance(full_name, str) else None,
            invite_code=secrets.token_hex(4).upper(),
            google_user_id=subject,
            auth_generation=0,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    session = issue_session(db, user, device_id=request.device_id)
    return _session_response(user, session.access_token, session.refresh_token)


@router.post("/refresh", response_model=SessionResponse)
def refresh_session(request: RefreshRequest, db: Session = Depends(get_db)):
    try:
        session = rotate_refresh(db, request.refresh_token)
    except RefreshCredentialError as error:
        raise HTTPException(status_code=401, detail="Invalid refresh credential") from error
    claims = decode_access_token(session.access_token)
    user = db.query(User).filter(User.id == int(claims["sub"])).one()
    return _session_response(user, session.access_token, session.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(request: LogoutRequest, db: Session = Depends(get_db)):
    try:
        revoke_refresh(db, request.refresh_token)
    except RefreshCredentialError:
        pass
    return None
