import json
import sqlite3
from datetime import datetime, timezone
from typing import Any
from ..models.domain import MissionStatus, StepStatus
from ..models.schemas import (
    ClarificationQuestion,
    MissionPlanResponse,
    MissionResponse,
    MissionStepResponse,
)


def _row_to_mission(
    m_row: sqlite3.Row,
    step_rows: list[sqlite3.Row],
    clarification_rows: list[sqlite3.Row],
) -> MissionResponse:
    """Convert database rows into a validated MissionResponse schema."""
    steps = [
        MissionStepResponse(
            id=s["id"],
            title=s["title"],
            description=s["description"],
            depends_on=json.loads(s["depends_on_json"]),
            expected_output=s["expected_output"],
            status=StepStatus(s["status"]),
            error_message=s["error_message"],
            result_text=s["result_text"],
            completed_at=s["completed_at"],
        )
        for s in step_rows
    ]

    clarifications = [
        ClarificationQuestion(
            id=c["id"],
            question=c["question"],
            answer=c["answer"],
        )
        for c in clarification_rows
    ]

    return MissionResponse(
        id=m_row["id"],
        goal=m_row["goal"],
        title=m_row["title"],
        status=MissionStatus(m_row["status"]),
        session_id=m_row["session_id"],
        plan=MissionPlanResponse(version=1, steps=steps),
        clarifications=clarifications,
        result_summary=m_row["result_summary"],
        failure_reason=m_row["failure_reason"],
        created_at=m_row["created_at"],
        updated_at=m_row["updated_at"],
        approved_by_user=bool(m_row["approved_by_user"]),
    )


class MissionRepository:
    """SQLite data access layer enforcing session isolation and transactional persistence."""

    def __init__(self, conn: sqlite3.Connection):
        self.conn = conn

    def create_mission(
        self,
        mission_id: str,
        session_id: str,
        goal: str,
        title: str,
        status: MissionStatus,
        client_request_id: str | None = None,
        context: dict[str, Any] | None = None,
        steps: list[dict[str, Any]] | None = None,
        clarifications: list[dict[str, Any]] | None = None,
    ) -> MissionResponse:
        """Atomically persist a new mission record with its steps and clarifications."""
        now = datetime.now(timezone.utc).isoformat()
        context_json = json.dumps(context) if context else None

        self.conn.execute(
            """
            INSERT INTO missions (
                id, session_id, goal, title, status, client_request_id,
                context_json, approved_by_user, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
            """,
            (
                mission_id,
                session_id,
                goal,
                title,
                status.value,
                client_request_id,
                context_json,
                now,
                now,
            ),
        )

        if steps:
            for i, step in enumerate(steps):
                self.conn.execute(
                    """
                    INSERT INTO mission_steps (
                        id, mission_id, step_order, title, description,
                        depends_on_json, expected_output, status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        step["id"],
                        mission_id,
                        i,
                        step["title"],
                        step["description"],
                        json.dumps(step.get("depends_on", [])),
                        step.get("expected_output", ""),
                        step.get("status", StepStatus.PENDING.value),
                    ),
                )

        if clarifications:
            for i, q in enumerate(clarifications):
                self.conn.execute(
                    """
                    INSERT INTO clarification_questions (
                        id, mission_id, question_order, question, answer
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        q["id"],
                        mission_id,
                        i,
                        q["question"],
                        q.get("answer"),
                    ),
                )

        created = self.get_mission_by_id(session_id, mission_id)
        assert created is not None
        return created

    def get_mission_by_id(self, session_id: str, mission_id: str) -> MissionResponse | None:
        """Fetch mission by ID with strict session ownership check."""
        cursor = self.conn.execute(
            "SELECT * FROM missions WHERE id = ? AND session_id = ?",
            (mission_id, session_id),
        )
        m_row = cursor.fetchone()
        if not m_row:
            return None

        step_cursor = self.conn.execute(
            "SELECT * FROM mission_steps WHERE mission_id = ? ORDER BY step_order ASC",
            (mission_id,),
        )
        step_rows = step_cursor.fetchall()

        q_cursor = self.conn.execute(
            "SELECT * FROM clarification_questions WHERE mission_id = ? ORDER BY question_order ASC",
            (mission_id,),
        )
        q_rows = q_cursor.fetchall()

        return _row_to_mission(m_row, step_rows, q_rows)

    def find_by_client_request_id(
        self, session_id: str, client_request_id: str
    ) -> MissionResponse | None:
        """Find an existing mission by client idempotency key within the caller session."""
        cursor = self.conn.execute(
            "SELECT id FROM missions WHERE session_id = ? AND client_request_id = ?",
            (session_id, client_request_id),
        )
        row = cursor.fetchone()
        if not row:
            return None
        return self.get_mission_by_id(session_id, row["id"])

    def list_missions(
        self, session_id: str, limit: int = 50, offset: int = 0
    ) -> tuple[list[MissionResponse], int]:
        """List missions belonging to the given session, ordered by updated_at desc."""
        count_cursor = self.conn.execute(
            "SELECT COUNT(*) as count FROM missions WHERE session_id = ?",
            (session_id,),
        )
        total = count_cursor.fetchone()["count"]

        cursor = self.conn.execute(
            """
            SELECT id FROM missions
            WHERE session_id = ?
            ORDER BY updated_at DESC
            LIMIT ? OFFSET ?
            """,
            (session_id, limit, offset),
        )
        rows = cursor.fetchall()

        missions: list[MissionResponse] = []
        for r in rows:
            m = self.get_mission_by_id(session_id, r["id"])
            if m:
                missions.append(m)

        return missions, total

    def update_status(
        self,
        session_id: str,
        mission_id: str,
        new_status: MissionStatus,
        approved_by_user: bool | None = None,
        failure_reason: str | None = None,
        result_summary: str | None = None,
        clear_failure_reason: bool = False,
    ) -> MissionResponse | None:
        """Update mission state and optional metadata while updating updated_at timestamp."""
        existing = self.get_mission_by_id(session_id, mission_id)
        if not existing:
            return None

        now = datetime.now(timezone.utc).isoformat()
        approved_val = (
            int(approved_by_user)
            if approved_by_user is not None
            else int(existing.approved_by_user)
        )
        if clear_failure_reason:
            fail_val = None
        else:
            fail_val = failure_reason if failure_reason is not None else existing.failure_reason
        res_val = result_summary if result_summary is not None else existing.result_summary

        self.conn.execute(
            """
            UPDATE missions
            SET status = ?, approved_by_user = ?, failure_reason = ?, result_summary = ?, updated_at = ?
            WHERE id = ? AND session_id = ?
            """,
            (
                new_status.value,
                approved_val,
                fail_val,
                res_val,
                now,
                mission_id,
                session_id,
            ),
        )

        return self.get_mission_by_id(session_id, mission_id)
