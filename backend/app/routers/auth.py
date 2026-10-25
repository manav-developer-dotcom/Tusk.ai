from typing import Optional
from fastapi import APIRouter, Depends, Header
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from ..models.user import (
    AuthResponse,
    TokenRefreshRequest,
    TokenResponse,
    UserLoginRequest,
    UserRegisterRequest,
    UserResponse,
)
from ..services.auth_service import AuthService, InvalidTokenError


router = APIRouter(prefix="/v1/auth", tags=["auth"])
bearer_scheme = HTTPBearer(auto_error=False)


def get_auth_service() -> AuthService:
    """Dependency provider for AuthService."""
    return AuthService()


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    auth_service: AuthService = Depends(get_auth_service),
) -> UserResponse:
    """Dependency that extracts and verifies Bearer token, returning the authenticated user."""
    if not credentials or not credentials.credentials:
        raise InvalidTokenError("Authorization header with Bearer token is required.")
    return auth_service.get_user_from_token(credentials.credentials)


def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    auth_service: AuthService = Depends(get_auth_service),
) -> Optional[UserResponse]:
    """Dependency that optionally extracts user if valid Bearer token is provided."""
    if not credentials or not credentials.credentials:
        return None
    try:
        return auth_service.get_user_from_token(credentials.credentials)
    except Exception:
        return None


@router.post("/register", response_model=AuthResponse, status_code=201)
async def register(
    payload: UserRegisterRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> AuthResponse:
    """Create a new user account and return fresh session tokens."""
    return auth_service.register(payload)


@router.post("/login", response_model=AuthResponse, status_code=200)
async def login(
    payload: UserLoginRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> AuthResponse:
    """Authenticate with email and password and return session tokens."""
    return auth_service.login(payload)


@router.post("/refresh", response_model=TokenResponse, status_code=200)
async def refresh_token(
    payload: TokenRefreshRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> TokenResponse:
    """Obtain a new access token using a valid refresh token."""
    return auth_service.refresh(payload)


@router.get("/me", response_model=UserResponse, status_code=200)
async def get_my_profile(
    current_user: UserResponse = Depends(get_current_user),
) -> UserResponse:
    """Return the profile of the currently authenticated user."""
    return current_user
