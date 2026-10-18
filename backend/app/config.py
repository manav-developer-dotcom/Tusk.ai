import os
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment or defaults."""
    env: str = "development"
    host: str = "0.0.0.0"
    port: int = 8000
    db_path: str = "data/tusk.db"
    cors_origins: list[str] = ["*"]
    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_prefix="TUSK_",
        env_file=".env",
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


settings = Settings()
