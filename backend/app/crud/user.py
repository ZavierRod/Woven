from sqlalchemy.orm import Session
from sqlalchemy import or_
from typing import Optional
import secrets
from passlib.context import CryptContext

from app.models.user import User
from app.schemas.auth import SignUpRequest

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    """Hash a password using bcrypt."""
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash."""
    return pwd_context.verify(plain_password, hashed_password)


class UserCRUD:
    def get_by_id(self, db: Session, user_id: int) -> Optional[User]:
        """Get a user by their ID."""
        return db.query(User).filter(User.id == user_id).first()

    def get_by_email(self, db: Session, email: str) -> Optional[User]:
        """Get a user by their email."""
        return db.query(User).filter(User.email == email.lower()).first()

    def get_by_username(self, db: Session, username: str) -> Optional[User]:
        """Get a user by their username."""
        return db.query(User).filter(User.username == username.lower()).first()

    def get_by_email_or_username(self, db: Session, identifier: str) -> Optional[User]:
        """Get a user by email or username."""
        identifier = identifier.lower().strip()
        return db.query(User).filter(
            or_(User.email == identifier, User.username == identifier)
        ).first()

    def get_by_invite_code(self, db: Session, invite_code: str) -> Optional[User]:
        """Get a user by their invite code."""
        return db.query(User).filter(User.invite_code == invite_code).first()

    def get_by_apple_id(self, db: Session, apple_user_id: str) -> Optional[User]:
        """Get a user by their Apple user ID (for future use)."""
        return db.query(User).filter(User.apple_user_id == apple_user_id).first()

    def create(self, db: Session, signup: SignUpRequest) -> User:
        """Create a new user with email/password."""
        # Generate invite code
        invite_code = secrets.token_hex(4).upper()

        db_user = User(
            username=signup.username.lower().strip(),
            email=signup.email.lower().strip(),
            password_hash=hash_password(signup.password),
            full_name=signup.full_name,
            invite_code=invite_code,
        )
        db.add(db_user)
        db.commit()
        db.refresh(db_user)
        return db_user

    def authenticate(self, db: Session, identifier: str, password: str) -> Optional[User]:
        """Authenticate user by email/username and password."""
        user = self.get_by_email_or_username(db, identifier)
        if not user:
            return None
        if not verify_password(password, user.password_hash):
            return None
        return user

    def update_name(self, db: Session, user: User, full_name: str) -> User:
        """Update user's full name."""
        user.full_name = full_name
        db.commit()
        db.refresh(user)
        return user

    def email_exists(self, db: Session, email: str) -> bool:
        """Check if email is already registered."""
        return self.get_by_email(db, email) is not None

    def username_exists(self, db: Session, username: str) -> bool:
        """Check if username is already taken."""
        return self.get_by_username(db, username) is not None


# Singleton instance
user_crud = UserCRUD()
