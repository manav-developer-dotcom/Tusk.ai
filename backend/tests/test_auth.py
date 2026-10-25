import time
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.services.auth_service import (
    hash_password,
    verify_password,
    create_access_token,
    decode_token,
    InvalidTokenError,
)


def test_password_hashing():
    """Verify bcrypt password hashing generates valid salted hashes that verify correctly."""
    plain = "SuperSecurePassword123!"
    hashed = hash_password(plain)
    assert hashed != plain
    assert hashed.startswith("$2b$")
    assert verify_password(plain, hashed) is True
    assert verify_password("WrongPassword123!", hashed) is False


def test_jwt_token_creation_and_decoding():
    """Verify JWT access token issuance, claims embedding, and verification."""
    user_id = "usr_test123"
    email = "test@tusk.ai"
    token, expires_in = create_access_token(user_id, email)
    assert isinstance(token, str)
    assert expires_in == settings.access_token_expire_minutes * 60

    payload = decode_token(token, expected_type="access")
    assert payload["sub"] == user_id
    assert payload["email"] == email
    assert payload["type"] == "access"
    assert payload["exp"] > time.time()


def test_jwt_decoding_invalid_signature():
    """Verify decoding a token with an invalid or tampered signature raises InvalidTokenError."""
    user_id = "usr_test123"
    email = "test@tusk.ai"
    token, _ = create_access_token(user_id, email)
    tampered_token = token[:-5] + "XXXXX"
    with pytest.raises(InvalidTokenError):
        decode_token(tampered_token)


def test_register_success(client: TestClient):
    """Registering a new account returns 201 Created and JWT session tokens."""
    payload = {
        "email": "developer@tusk.ai",
        "password": "Password1234!",
        "display_name": "Tusk Developer",
    }
    resp = client.post("/v1/auth/register", json=payload)
    assert resp.status_code == 201
    data = resp.json()

    assert "user" in data
    assert "tokens" in data
    assert data["user"]["email"] == "developer@tusk.ai"
    assert data["user"]["display_name"] == "Tusk Developer"
    assert data["user"]["id"].startswith("usr_")

    tokens = data["tokens"]
    assert "access_token" in tokens
    assert "refresh_token" in tokens
    assert tokens["token_type"] == "bearer"
    assert tokens["expires_in"] == settings.access_token_expire_minutes * 60


def test_register_duplicate_email_conflict(client: TestClient):
    """Registering with an already existing email returns 409 Conflict with structured error."""
    payload = {
        "email": "unique@tusk.ai",
        "password": "Password1234!",
        "display_name": "Unique User",
    }
    first_resp = client.post("/v1/auth/register", json=payload)
    assert first_resp.status_code == 201

    # Attempt second registration with same email (case-insensitive)
    payload_dup = {
        "email": " UNIQUE@tusk.ai ",
        "password": "DifferentPassword567!",
    }
    dup_resp = client.post("/v1/auth/register", json=payload_dup)
    assert dup_resp.status_code == 409
    data = dup_resp.json()
    assert "error" in data
    assert data["error"]["code"] == "EMAIL_ALREADY_EXISTS"


def test_register_weak_password_validation(client: TestClient):
    """Registering with a password shorter than 8 characters returns 422 Validation Error."""
    payload = {
        "email": "test@tusk.ai",
        "password": "short",
    }
    resp = client.post("/v1/auth/register", json=payload)
    assert resp.status_code == 422
    data = resp.json()
    assert data["error"]["code"] == "VALIDATION_ERROR"


def test_register_invalid_email_validation(client: TestClient):
    """Registering with a malformed email returns 422 Validation Error."""
    payload = {
        "email": "not-an-email",
        "password": "ValidPassword1234!",
    }
    resp = client.post("/v1/auth/register", json=payload)
    assert resp.status_code == 422
    data = resp.json()
    assert data["error"]["code"] == "VALIDATION_ERROR"


def test_login_success(client: TestClient):
    """Authenticating with correct credentials returns 200 OK and JWT tokens."""
    client.post(
        "/v1/auth/register",
        json={"email": "login_test@tusk.ai", "password": "MySecretPassword123!"},
    )

    login_resp = client.post(
        "/v1/auth/login",
        json={"email": "login_test@tusk.ai", "password": "MySecretPassword123!"},
    )
    assert login_resp.status_code == 200
    data = login_resp.json()
    assert data["user"]["email"] == "login_test@tusk.ai"
    assert "access_token" in data["tokens"]
    assert "refresh_token" in data["tokens"]


def test_login_wrong_password_unauthorized(client: TestClient):
    """Login with an incorrect password returns 401 Unauthorized."""
    client.post(
        "/v1/auth/register",
        json={"email": "wrong_pw@tusk.ai", "password": "CorrectPassword123!"},
    )

    resp = client.post(
        "/v1/auth/login",
        json={"email": "wrong_pw@tusk.ai", "password": "WrongPassword999!"},
    )
    assert resp.status_code == 401
    data = resp.json()
    assert data["error"]["code"] == "INVALID_CREDENTIALS"


def test_login_nonexistent_email_unauthorized(client: TestClient):
    """Login with an email that does not exist returns 401 Unauthorized."""
    resp = client.post(
        "/v1/auth/login",
        json={"email": "ghost@tusk.ai", "password": "AnyPassword123!"},
    )
    assert resp.status_code == 401
    data = resp.json()
    assert data["error"]["code"] == "INVALID_CREDENTIALS"


def test_refresh_token_lifecycle(client: TestClient):
    """Refreshing an access token with a valid refresh token returns refreshed tokens."""
    reg_resp = client.post(
        "/v1/auth/register",
        json={"email": "refresher@tusk.ai", "password": "ValidPassword123!"},
    )
    refresh_tok = reg_resp.json()["tokens"]["refresh_token"]

    ref_resp = client.post(
        "/v1/auth/refresh",
        json={"refresh_token": refresh_tok},
    )
    assert ref_resp.status_code == 200
    data = ref_resp.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


def test_refresh_token_invalid_or_wrong_type(client: TestClient):
    """Submitting an access token to the refresh endpoint is rejected with 401 Unauthorized."""
    reg_resp = client.post(
        "/v1/auth/register",
        json={"email": "refresher_bad@tusk.ai", "password": "ValidPassword123!"},
    )
    access_tok = reg_resp.json()["tokens"]["access_token"]

    # Passing access token to refresh endpoint must fail because type is 'access', not 'refresh'
    ref_resp = client.post(
        "/v1/auth/refresh",
        json={"refresh_token": access_tok},
    )
    assert ref_resp.status_code == 401
    data = ref_resp.json()
    assert data["error"]["code"] == "INVALID_TOKEN"


def test_get_current_user_profile(client: TestClient):
    """GET /v1/auth/me returns the authenticated user's profile with a valid Bearer token."""
    reg_resp = client.post(
        "/v1/auth/register",
        json={"email": "profile@tusk.ai", "password": "ValidPassword123!", "display_name": "Profile User"},
    )
    access_tok = reg_resp.json()["tokens"]["access_token"]
    user_id = reg_resp.json()["user"]["id"]

    me_resp = client.get(
        "/v1/auth/me",
        headers={"Authorization": f"Bearer {access_tok}"},
    )
    assert me_resp.status_code == 200
    user_data = me_resp.json()
    assert user_data["id"] == user_id
    assert user_data["email"] == "profile@tusk.ai"
    assert user_data["display_name"] == "Profile User"


def test_get_current_user_unauthorized_cases(client: TestClient):
    """GET /v1/auth/me rejects requests with missing or invalid Authorization headers."""
    # Missing header
    resp_no_auth = client.get("/v1/auth/me")
    assert resp_no_auth.status_code == 401
    assert resp_no_auth.json()["error"]["code"] == "INVALID_TOKEN"

    # Invalid / corrupted token
    resp_bad_auth = client.get(
        "/v1/auth/me",
        headers={"Authorization": "Bearer not_a_valid_jwt_token"},
    )
    assert resp_bad_auth.status_code == 401
    assert resp_bad_auth.json()["error"]["code"] == "INVALID_TOKEN"
