import os
from pathlib import Path
from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment or defaults."""
    env: str = "development"
    host: str = "0.0.0.0"
    port: int = 8000
    db_path: str = "data/tusk.db"
    artifacts_dir: str = "data/artifacts"
    cors_origins: list[str] = ["*"]
    log_level: str = "INFO"

    # JWT Authentication & Identity Configuration
    jwt_secret_key: str = Field(
        default="tusk_development_secret_key_at_least_32_bytes_long_change_in_production",
        validation_alias=AliasChoices("JWT_SECRET_KEY", "TUSK_JWT_SECRET", "JWT_SECRET"),
        description="Secret key for signing authentication JWTs"
    )
    jwt_algorithm: str = Field(
        default="HS256",
        validation_alias=AliasChoices("JWT_ALGORITHM", "TUSK_JWT_ALGORITHM"),
        description="Algorithm used for JWT signing"
    )
    access_token_expire_minutes: int = Field(
        default=30,
        validation_alias=AliasChoices("ACCESS_TOKEN_EXPIRE_MINUTES", "TUSK_ACCESS_TOKEN_EXPIRE_MINUTES"),
        description="Lifetime of access token in minutes"
    )
    refresh_token_expire_days: int = Field(
        default=7,
        validation_alias=AliasChoices("REFRESH_TOKEN_EXPIRE_DAYS", "TUSK_REFRESH_TOKEN_EXPIRE_DAYS"),
        description="Lifetime of refresh token in days"
    )
    auth_required: bool = Field(
        default=False,
        validation_alias=AliasChoices("AUTH_REQUIRED", "TUSK_AUTH_REQUIRED"),
        description="Whether authentication is strictly required on all protected endpoints"
    )

    # Real AI Provider Configuration
    gemini_api_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices("GEMINI_API_KEY", "TUSK_GEMINI_API_KEY"),
        description="Google Gemini API key for real AI planning and execution"
    )
    gemini_model: str = Field(
        default="gemini-3.5-flash",
        validation_alias=AliasChoices("TUSK_GEMINI_MODEL", "GEMINI_MODEL"),
        description="Supported, cost-effective Gemini model identifier"
    )

    # External Agent Interoperability (uAgents / Fetch.ai)
    agent_enabled: bool = Field(
        default=True,
        validation_alias=AliasChoices("AGENT_ENABLED", "TUSK_AGENT_ENABLED"),
        description="Enable or disable uAgents external interoperability adapter"
    )
    agent_name: str = Field(
        default="tusk_action_agent",
        validation_alias=AliasChoices("AGENT_NAME", "TUSK_AGENT_NAME"),
        description="Public discovery name for the Tusk.ai external agent"
    )
    agent_seed: str | None = Field(
        default=None,
        validation_alias=AliasChoices("AGENT_SEED", "TUSK_AGENT_SEED"),
        description="Mnemonic recovery seed for deterministic agent address generation"
    )
    agent_port: int = Field(
        default=8001,
        validation_alias=AliasChoices("AGENT_PORT", "TUSK_AGENT_PORT"),
        description="Port for the external uAgents HTTP endpoint"
    )
    agent_endpoint: str | None = Field(
        default=None,
        validation_alias=AliasChoices("AGENT_ENDPOINT", "TUSK_AGENT_ENDPOINT"),
        description="Public or LAN URL endpoint for the agent (e.g. http://127.0.0.1:8001/submit)"
    )
    agent_mailbox_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices("AGENT_MAILBOX_KEY", "TUSK_AGENT_MAILBOX_KEY"),
        description="Agentverse Mailbox API key for asynchronous cloud discovery and messaging"
    )


    model_config = SettingsConfigDict(
        env_prefix="TUSK_",
        env_file=(str(Path(__file__).resolve().parent.parent / ".env"), ".env"),
        env_file_encoding="utf-8",
        extra="ignore"
    )

    @property
    def absolute_db_path(self) -> Path:
        """Resolve the SQLite database path relative to backend root."""
        base_dir = Path(__file__).resolve().parent.parent
        p = Path(self.db_path)
        if not p.is_absolute():
            p = base_dir / p
        p.parent.mkdir(parents=True, exist_ok=True)
        return p

    @property
    def absolute_artifacts_dir(self) -> Path:
        """Resolve the directory path for persistent deliverables and artifacts."""
        base_dir = Path(__file__).resolve().parent.parent
        p = Path(self.artifacts_dir)
        if not p.is_absolute():
            p = base_dir / p
        p.mkdir(parents=True, exist_ok=True)
        return p


settings = Settings()
