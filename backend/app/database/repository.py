import json
import sqlite3
from datetime import datetime, timezone
from typing import Any
from ..models.domain import MissionStatus, StepStatus
from ..models.schemas import (
    ArtifactItem,
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

    planner_mode = "development"
    if m_row["context_json"]:
        try:
            ctx_data = json.loads(m_row["context_json"])
            planner_mode = ctx_data.get("planner_mode", "development")
        except Exception:
            pass

    return MissionResponse(
        id=m_row["id"],
        goal=m_row["goal"],
        title=m_row["title"],
        status=MissionStatus(m_row["status"]),
        session_id=m_row["session_id"],
        plan=MissionPlanResponse(version=1, planner_mode=planner_mode, steps=steps),
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

    def update_step_status(
        self,
        mission_id: str,
        step_id: str,
        status: StepStatus,
        result_text: str | None = None,
        error_message: str | None = None,
    ) -> None:
        """Update an individual step's execution status, result text, and error."""
        completed_at = (
            datetime.now(timezone.utc).isoformat()
            if status == StepStatus.COMPLETED
            else None
        )
        self.conn.execute(
            """
            UPDATE mission_steps
            SET status = ?, result_text = ?, error_message = ?, completed_at = ?
            WHERE id = ? AND mission_id = ?
            """,
            (
                status.value,
                result_text,
                error_message,
                completed_at,
                step_id,
                mission_id,
            ),
        )

    def create_artifact(
        self,
        artifact_id: str,
        mission_id: str,
        step_id: str | None,
        session_id: str,
        media_type: str,
        name: str,
        file_path: str,
        size_bytes: int,
    ) -> ArtifactItem:
        """Persist a deliverable artifact record associated with a mission and session."""
        now = datetime.now(timezone.utc).isoformat()
        self.conn.execute(
            """
            INSERT INTO artifacts (
                id, mission_id, step_id, session_id, media_type, name, file_path, size_bytes, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                artifact_id,
                mission_id,
                step_id,
                session_id,
                media_type,
                name,
                file_path,
                size_bytes,
                now,
            ),
        )
        return ArtifactItem(
            id=artifact_id,
            mission_id=mission_id,
            step_id=step_id,
            media_type=media_type,
            name=name,
            size_bytes=size_bytes,
            url=f"/v1/artifacts/{artifact_id}",
            created_at=now,
        )

    def list_artifacts(self, session_id: str, mission_id: str) -> list[ArtifactItem]:
        """List all artifacts generated for a mission within the caller's session."""
        cursor = self.conn.execute(
            """
            SELECT id, mission_id, step_id, media_type, name, size_bytes, created_at
            FROM artifacts
            WHERE mission_id = ? AND session_id = ?
            ORDER BY created_at ASC
            """,
            (mission_id, session_id),
        )
        rows = cursor.fetchall()
        return [
            ArtifactItem(
                id=r["id"],
                mission_id=r["mission_id"],
                step_id=r["step_id"],
                media_type=r["media_type"],
                name=r["name"],
                size_bytes=r["size_bytes"],
                url=f"/v1/artifacts/{r['id']}",
                created_at=r["created_at"],
            )
            for r in rows
        ]

    def get_artifact(
        self, session_id: str, artifact_id: str
    ) -> tuple[ArtifactItem, str] | None:
        """Retrieve artifact metadata and local file path ensuring session isolation."""
        cursor = self.conn.execute(
            """
            SELECT id, mission_id, step_id, media_type, name, file_path, size_bytes, created_at
            FROM artifacts
            WHERE id = ? AND session_id = ?
            """,
            (artifact_id, session_id),
        )
        row = cursor.fetchone()
        if not row:
            return None

        item = ArtifactItem(
            id=row["id"],
            mission_id=row["mission_id"],
            step_id=row["step_id"],
            media_type=row["media_type"],
            name=row["name"],
            size_bytes=row["size_bytes"],
            url=f"/v1/artifacts/{row['id']}",
            created_at=row["created_at"],
        )
        return item, row["file_path"]
