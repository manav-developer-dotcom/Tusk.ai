import os
import tempfile
from pathlib import Path
from typing import Generator
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.connection import init_db
from app.main import app


@pytest.fixture
def temp_db_path() -> Generator[Path, None, None]:
    """Provide an isolated temporary SQLite database for each test."""
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
        db_file = Path(f.name)

    orig_db = settings.db_path
    settings.db_path = str(db_file)
    init_db(db_file)

    yield db_file

    settings.db_path = orig_db
    if db_file.exists():
        try:
            db_file.unlink()
        except Exception:
            pass


@pytest.fixture
def client(temp_db_path: Path) -> Generator[TestClient, None, None]:
    """TestClient configured with isolated SQLite database."""
    with TestClient(app) as test_client:
        yield test_client
