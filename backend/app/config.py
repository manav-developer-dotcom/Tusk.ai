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

    # Real AI Provider Configuration
    gemini_api_key: str | None = Field(
        default=None,
        validation_alias=AliasChoices("GEMINI_API_KEY", "TUSK_GEMINI_API_KEY"),
        description="Google Gemini API key for real AI planning and execution"
    )
    gemini_model: str = Field(
        default="gemini-3.8-flash",
        validation_alias=AliasChoices("TUSK_GEMINI_MODEL", "GEMINI_MODEL"),
        description="Supported, cost-effective Gemini model identifier"
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
