import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Generator
from ..config import settings


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS missions (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    goal TEXT NOT NULL,
    title TEXT NOT NULL,
    status TEXT NOT NULL,
    client_request_id TEXT,
    context_json TEXT,
    result_summary TEXT,
    failure_reason TEXT,
    approved_by_user INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS mission_steps (
    id TEXT PRIMARY KEY,
    mission_id TEXT NOT NULL,
    step_order INTEGER NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    depends_on_json TEXT NOT NULL DEFAULT '[]',
    expected_output TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL,
    error_message TEXT,
    result_text TEXT,
    completed_at TEXT,
    FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS clarification_questions (
    id TEXT PRIMARY KEY,
    mission_id TEXT NOT NULL,
    question_order INTEGER NOT NULL,
    question TEXT NOT NULL,
    answer TEXT,
    FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_missions_session ON missions(session_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_missions_client_req ON missions(session_id, client_request_id);
CREATE INDEX IF NOT EXISTS idx_steps_mission ON mission_steps(mission_id, step_order ASC);
CREATE INDEX IF NOT EXISTS idx_clarifications_mission ON clarification_questions(mission_id, question_order ASC);
"""


def get_db_path() -> Path:
    """Return the absolute path to the SQLite database file."""
    return settings.absolute_db_path


def init_db(db_path: Path | None = None) -> None:
    """Initialize SQLite tables and indexes."""
    target_path = db_path or get_db_path()
    target_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(str(target_path)) as conn:
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.execute("PRAGMA foreign_keys=ON;")
        conn.executescript(SCHEMA_SQL)
        conn.commit()


@contextmanager
def get_db_connection(db_path: Path | None = None) -> Generator[sqlite3.Connection, None, None]:
    """Context manager yielding a SQLite connection configured with Row factory."""
    target_path = db_path or get_db_path()
    conn = sqlite3.connect(str(target_path), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON;")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
