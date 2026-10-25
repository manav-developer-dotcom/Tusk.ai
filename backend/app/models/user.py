import re
from typing import Optional
from pydantic import BaseModel, Field, field_validator


EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$")


class UserRegisterRequest(BaseModel):
    """Payload for creating a new user account."""
    email: str = Field(..., min_length=5, max_length=255, description="Unique account email address")
    password: str = Field(..., min_length=8, max_length=128, description="Account password (min 8 characters)")
    display_name: Optional[str] = Field(default=None, max_length=100, description="Optional user display name")

    @field_validator("email")
    @classmethod
    def validate_email_format(cls, v: str) -> str:
        clean = v.strip().lower()
        if not EMAIL_REGEX.match(clean):
            raise ValueError("Invalid email address format.")
        return clean

    @field_validator("password")
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters long.")
        return v


class UserLoginRequest(BaseModel):
    """Payload for user authentication."""
    email: str = Field(..., min_length=5, max_length=255, description="Account email address")
    password: str = Field(..., min_length=1, max_length=128, description="Account password")

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class TokenRefreshRequest(BaseModel):
    """Payload for refreshing an expired access token."""
    refresh_token: str = Field(..., min_length=10, description="Valid refresh token")


class TokenResponse(BaseModel):
    """Authentication tokens returned upon successful login/registration."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserResponse(BaseModel):
    """Safe user profile response without credentials."""
    id: str
    email: str
    display_name: Optional[str] = None
    created_at: str


class AuthResponse(BaseModel):
    """Combined response returning user profile and session tokens."""
    user: UserResponse
    tokens: TokenResponse
