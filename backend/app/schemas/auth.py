from pydantic import BaseModel, EmailStr, field_validator
from typing import Optional
import re


class SignUpRequest(BaseModel):
    """Request body for user registration."""
    username: str
    email: EmailStr
    password: str
    full_name: Optional[str] = None

    @field_validator('username')
    @classmethod
    def validate_username(cls, v: str) -> str:
        v = v.strip().lower()
        if len(v) < 3:
            raise ValueError('Username must be at least 3 characters')
        if len(v) > 30:
            raise ValueError('Username must be less than 30 characters')
        if not re.match(r'^[a-z0-9_]+$', v):
            raise ValueError(
                'Username can only contain letters, numbers, and underscores')
        return v

    @field_validator('password')
    @classmethod
    def validate_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        return v


class LoginRequest(BaseModel):
    """Request body for login. Can use email or username."""
    identifier: str  # email or username
    password: str


class Token(BaseModel):
    """JWT token response."""
    access_token: str
    token_type: str = "bearer"


class AuthResponse(BaseModel):
    """Response for signup/login with token and user info."""
    access_token: str
    token_type: str = "bearer"
    user_id: int
    username: str
    email: str
    full_name: Optional[str] = None
    invite_code: str


# Keep for future Apple Sign In support
class AppleSignInRequest(BaseModel):
    identity_token: str
    first_name: Optional[str] = None
    last_name: Optional[str] = None
