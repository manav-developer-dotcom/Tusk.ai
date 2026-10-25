import sqlite3
import time
import uuid
from typing import Any, Optional
import bcrypt
import jwt

from ..config import settings
from ..database.connection import get_db_connection
from ..database.user_repository import UserRepository
from ..models.user import (
    AuthResponse,
    TokenRefreshRequest,
    TokenResponse,
    UserLoginRequest,
    UserRegisterRequest,
    UserResponse,
)


# ─────────────────────────────────────────────────────────────────────────────
# Custom Auth Exceptions (API_CONTRACT.md compliance)
# ─────────────────────────────────────────────────────────────────────────────

class AuthServiceException(Exception):
    """Base exception for authentication and identity operations."""
    def __init__(self, code: str, message: str, status_code: int = 400, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.retryable = retryable


class EmailAlreadyExistsError(AuthServiceException):
    def __init__(self, email: str):
        super().__init__(
            code="EMAIL_ALREADY_EXISTS",
            message=f"An account with email '{email}' already exists.",
            status_code=409,
            retryable=False,
        )


class InvalidCredentialsError(AuthServiceException):
    def __init__(self, message: str = "Invalid email or password."):
        super().__init__(
            code="INVALID_CREDENTIALS",
            message=message,
            status_code=401,
            retryable=False,
        )


class InvalidTokenError(AuthServiceException):
    def __init__(self, message: str = "Invalid or expired authentication token."):
        super().__init__(
            code="INVALID_TOKEN",
            message=message,
            status_code=401,
            retryable=False,
        )


# ─────────────────────────────────────────────────────────────────────────────
# Cryptographic Helpers
# ─────────────────────────────────────────────────────────────────────────────

def hash_password(password: str) -> str:
    """Hash a plaintext password using bcrypt with standard cost factor."""
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode("utf-8"), salt).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plaintext password against a stored bcrypt hash."""
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
    except Exception:
        return False


def create_access_token(user_id: str, email: str) -> tuple[str, int]:
    """Issue a signed JWT access token returning (token_string, expires_in_seconds)."""
    now = int(time.time())
    expires_in = settings.access_token_expire_minutes * 60
    exp = now + expires_in
    payload = {
        "sub": user_id,
        "email": email,
        "type": "access",
        "iat": now,
        "exp": exp,
    }
    token = jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    return token, expires_in


def create_refresh_token(user_id: str) -> str:
    """Issue a signed JWT refresh token."""
    now = int(time.time())
    exp = now + (settings.refresh_token_expire_days * 86400)
    payload = {
        "sub": user_id,
        "type": "refresh",
        "iat": now,
        "exp": exp,
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_token(token: str, expected_type: Optional[str] = None) -> dict[str, Any]:
    """Verify and decode a JWT token string."""
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )
    except jwt.ExpiredSignatureError:
        raise InvalidTokenError("Authentication token has expired.")
    except jwt.InvalidTokenError:
        raise InvalidTokenError("Invalid authentication token format or signature.")

    if expected_type and payload.get("type") != expected_type:
        raise InvalidTokenError(f"Expected '{expected_type}' token, but received '{payload.get('type')}'.")

    return payload


# ─────────────────────────────────────────────────────────────────────────────
# Authentication Service
# ─────────────────────────────────────────────────────────────────────────────

class AuthService:
    """Handles user registration, authentication, token lifecycle, and session identity."""

    def __init__(self, db_conn_factory=get_db_connection):
        self.db_conn_factory = db_conn_factory

    def register(self, req: UserRegisterRequest) -> AuthResponse:
        """Register a new user account with unique email and bcrypt-hashed password."""
        with self.db_conn_factory() as conn:
            repo = UserRepository(conn)
            existing = repo.get_by_email(req.email)
            if existing:
                raise EmailAlreadyExistsError(req.email)

            user_id = f"usr_{uuid.uuid4().hex[:16]}"
            hashed_pw = hash_password(req.password)
            user_data = repo.create_user(
                user_id=user_id,
                email=req.email,
                hashed_password=hashed_pw,
                display_name=req.display_name,
            )

        access_token, expires_in = create_access_token(user_id, req.email)
        refresh_token = create_refresh_token(user_id)

        user_resp = UserResponse(
            id=user_data["id"],
            email=user_data["email"],
            display_name=user_data["display_name"],
            created_at=user_data["created_at"],
        )
        token_resp = TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=expires_in,
        )
        return AuthResponse(user=user_resp, tokens=token_resp)

    def login(self, req: UserLoginRequest) -> AuthResponse:
        """Authenticate user credentials and return new session tokens."""
        with self.db_conn_factory() as conn:
            repo = UserRepository(conn)
            user_row = repo.get_by_email(req.email)

        if not user_row or not verify_password(req.password, user_row["hashed_password"]):
            raise InvalidCredentialsError("Invalid email or password.")

        user_id = user_row["id"]
        email = user_row["email"]
        access_token, expires_in = create_access_token(user_id, email)
        refresh_token = create_refresh_token(user_id)

        user_resp = UserResponse(
            id=user_id,
            email=email,
            display_name=user_row["display_name"],
            created_at=user_row["created_at"],
        )
        token_resp = TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=expires_in,
        )
        return AuthResponse(user=user_resp, tokens=token_resp)

    def refresh(self, req: TokenRefreshRequest) -> TokenResponse:
        """Verify refresh token and issue rotated tokens."""
        payload = decode_token(req.refresh_token, expected_type="refresh")
        user_id = payload.get("sub")
        if not user_id:
            raise InvalidTokenError("Refresh token missing subject identifier.")

        with self.db_conn_factory() as conn:
            repo = UserRepository(conn)
            user_row = repo.get_by_id(user_id)

        if not user_row:
            raise InvalidTokenError("User associated with refresh token no longer exists.")

        access_token, expires_in = create_access_token(user_id, user_row["email"])
        new_refresh_token = create_refresh_token(user_id)

        return TokenResponse(
            access_token=access_token,
            refresh_token=new_refresh_token,
            token_type="bearer",
            expires_in=expires_in,
        )

    def get_user_from_token(self, token: str) -> UserResponse:
        """Decode and validate an access token, returning the user profile."""
        payload = decode_token(token, expected_type="access")
        user_id = payload.get("sub")
        if not user_id:
            raise InvalidTokenError("Access token missing subject identifier.")

        with self.db_conn_factory() as conn:
            repo = UserRepository(conn)
            user_row = repo.get_by_id(user_id)

        if not user_row:
            raise InvalidTokenError("User associated with token no longer exists.")

        return UserResponse(
            id=user_row["id"],
            email=user_row["email"],
            display_name=user_row["display_name"],
            created_at=user_row["created_at"],
        )
