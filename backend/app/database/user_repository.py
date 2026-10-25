import sqlite3
from datetime import datetime, timezone
from typing import Any, Optional


class UserRepository:
    """SQLite data access layer for user accounts and credentials."""

    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn

    def create_user(
        self,
        user_id: str,
        email: str,
        hashed_password: str,
        display_name: Optional[str] = None,
    ) -> dict[str, Any]:
        """Atomically persist a new user record."""
        now = datetime.now(timezone.utc).isoformat()
        self.conn.execute(
            """
            INSERT INTO users (
                id, email, hashed_password, display_name, is_active, created_at, updated_at
            ) VALUES (?, ?, ?, ?, 1, ?, ?)
            """,
            (user_id, email.strip().lower(), hashed_password, display_name, now, now),
        )
        return {
            "id": user_id,
            "email": email.strip().lower(),
            "display_name": display_name,
            "is_active": 1,
            "created_at": now,
            "updated_at": now,
        }

    def get_by_email(self, email: str) -> Optional[sqlite3.Row]:
        """Fetch user record by normalized email."""
        cursor = self.conn.execute(
            "SELECT * FROM users WHERE email = ? AND is_active = 1",
            (email.strip().lower(),),
        )
        return cursor.fetchone()

    def get_by_id(self, user_id: str) -> Optional[sqlite3.Row]:
        """Fetch user record by user ID."""
        cursor = self.conn.execute(
            "SELECT * FROM users WHERE id = ? AND is_active = 1",
            (user_id,),
        )
        return cursor.fetchone()
