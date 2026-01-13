from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.deps import get_db
from app.schemas.auth import SignUpRequest, LoginRequest, AuthResponse, AppleSignInRequest, Token
from app.crud.user import user_crud
from app.core.security import create_access_token, verify_apple_token

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/signup", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def sign_up(request: SignUpRequest, db: Session = Depends(get_db)):
    """
    Register a new user with username, email, and password.
    """
    # Check if email already exists
    if user_crud.email_exists(db, request.email):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )

    # Check if username already exists
    if user_crud.username_exists(db, request.username):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already taken"
        )

    # Create user
    user = user_crud.create(db, request)

    # Generate token
    access_token = create_access_token(data={"sub": str(user.id)})

    return AuthResponse(
        access_token=access_token,
        user_id=user.id,
        username=user.username,
        email=user.email,
        full_name=user.full_name,
        invite_code=user.invite_code
    )


@router.post("/login", response_model=AuthResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    """
    Login with email or username and password.
    """
    user = user_crud.authenticate(db, request.identifier, request.password)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email/username or password"
        )

    # Generate token
    access_token = create_access_token(data={"sub": str(user.id)})

    return AuthResponse(
        access_token=access_token,
        user_id=user.id,
        username=user.username,
        email=user.email,
        full_name=user.full_name,
        invite_code=user.invite_code
    )


# Keep Apple Sign In endpoint for future use (commented out)
# @router.post("/apple", response_model=Token)
# def sign_in_with_apple(request: AppleSignInRequest, db: Session = Depends(get_db)):
#     """Sign in or register with Apple Sign In."""
#     apple_data = verify_apple_token(request.identity_token)
#     if not apple_data:
#         raise HTTPException(
#             status_code=status.HTTP_401_UNAUTHORIZED,
#             detail="Invalid Apple authentication credentials"
#         )
#     # ... rest of Apple Sign In logic
