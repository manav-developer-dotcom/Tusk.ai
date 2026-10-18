import time
import uuid
import sqlite3
from typing import Any
from ..config import settings
from ..database.repository import MissionRepository
from ..models.domain import MissionStatus, StepStatus, can_transition
from ..models.schemas import (
    ArtifactItem,
    ArtifactListResponse,
    MissionListResponse,
    MissionResponse,
    MissionStatusResponse,
    StepStateItem,
)
from .ai_planner import AIPlannerService
from .execution_engine import ExecutionEngine
from .llm_provider import GeminiProvider, LLMProvider
from .planner import RuleBasedPlannerService


# ─────────────────────────────────────────────────────────────────────────────
# Custom Domain Exceptions
# ─────────────────────────────────────────────────────────────────────────────

class MissionServiceException(Exception):
    def __init__(self, code: str, message: str, status_code: int = 400, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.retryable = retryable


class MissionNotFoundError(MissionServiceException):
    def __init__(self, mission_id: str):
        super().__init__(
            code="MISSION_NOT_FOUND",
            message=f"Mission '{mission_id}' was not found or belongs to another session.",
            status_code=404,
            retryable=False,
        )


class InvalidStateTransitionError(MissionServiceException):
    def __init__(self, current: MissionStatus, target: MissionStatus):
        super().__init__(
            code="INVALID_STATE_TRANSITION",
            message=f"Cannot transition mission from '{current.value}' to '{target.value}'.",
            status_code=409,
            retryable=False,
        )


# ─────────────────────────────────────────────────────────────────────────────
# Mission Service
# ─────────────────────────────────────────────────────────────────────────────

class MissionService:
    """Core domain application service coordinating planning, execution, and state persistence."""

    def __init__(
        self,
        conn: sqlite3.Connection,
        provider: LLMProvider | None = None,
        planner: AIPlannerService | None = None,
    ):
        self.conn = conn
        self.repo = MissionRepository(conn)
        self.provider = provider or GeminiProvider(settings.gemini_api_key, model=settings.gemini_model)
        self.planner = planner or AIPlannerService(self.provider, model_name=settings.gemini_model)

    async def create_mission(
        self,
        session_id: str,
        goal: str,
        context: dict[str, Any] | None = None,
        client_request_id: str | None = None,
    ) -> MissionResponse:
        """Create a new mission with Gemini AI generated plan or clarification state."""
        # 1. Idempotency check
        if client_request_id:
            existing = self.repo.find_by_client_request_id(session_id, client_request_id)
            if existing:
                return existing

        # 2. Identifier
        ts = int(time.time() * 1000)
        random_suffix = uuid.uuid4().hex[:6]
        mission_id = f"mission_{ts}_{random_suffix}"
        clean_goal = goal.strip()

        # 3. AI Planning & Clarification Assessment
        plan_result = await self.planner.plan(mission_id, clean_goal, context)
        status = (
            MissionStatus.NEEDS_CLARIFICATION
            if plan_result.needs_clarification
            else MissionStatus.READY_FOR_APPROVAL
        )

        # 4. Atomic persistence
        return self.repo.create_mission(
            mission_id=mission_id,
            session_id=session_id,
            goal=clean_goal,
            title=plan_result.title,
            status=status,
            client_request_id=client_request_id,
            context=context,
            steps=plan_result.steps,
            clarifications=plan_result.clarifications,
        )

    def get_mission(self, session_id: str, mission_id: str) -> MissionResponse:
        """Retrieve a single mission by ID; verifies session ownership."""
        mission = self.repo.get_mission_by_id(session_id, mission_id)
        if not mission:
            raise MissionNotFoundError(mission_id)
        return mission

    def list_missions(
        self, session_id: str, limit: int = 50, offset: int = 0
    ) -> MissionListResponse:
        """List all missions belonging to the active session."""
        missions, total = self.repo.list_missions(session_id, limit, offset)
        return MissionListResponse(missions=missions, total=total)

    def approve_mission(self, session_id: str, mission_id: str) -> MissionResponse:
        """Approve a planned mission; validates state machine transition."""
        mission = self.get_mission(session_id, mission_id)
        if not can_transition(mission.status, MissionStatus.APPROVED):
            raise InvalidStateTransitionError(mission.status, MissionStatus.APPROVED)

        updated = self.repo.update_status(
            session_id=session_id,
            mission_id=mission_id,
            new_status=MissionStatus.APPROVED,
            approved_by_user=True,
        )
        assert updated is not None
        return updated

    async def execute_mission(self, session_id: str, mission_id: str) -> MissionResponse:
        """Execute an approved mission using allowlisted backend tools and generate deliverables."""
        mission = self.get_mission(session_id, mission_id)
        if mission.status not in (MissionStatus.APPROVED, MissionStatus.RUNNING):
            raise InvalidStateTransitionError(mission.status, MissionStatus.RUNNING)

        engine = ExecutionEngine(self.conn, self.provider)
        return await engine.execute_mission(session_id, mission_id)

    def cancel_mission(
        self, session_id: str, mission_id: str, reason: str = "Cancelled by user."
    ) -> MissionResponse:
        """Cancel a mission if not in a terminal state."""
        mission = self.get_mission(session_id, mission_id)
        if not can_transition(mission.status, MissionStatus.CANCELLED):
            raise InvalidStateTransitionError(mission.status, MissionStatus.CANCELLED)

        updated = self.repo.update_status(
            session_id=session_id,
            mission_id=mission_id,
            new_status=MissionStatus.CANCELLED,
            failure_reason=reason,
        )
        assert updated is not None
        return updated

    def retry_mission(self, session_id: str, mission_id: str) -> MissionResponse:
        """Retry a failed mission by resetting steps to pending and returning state to readyForApproval."""
        mission = self.get_mission(session_id, mission_id)
        if not can_transition(mission.status, MissionStatus.READY_FOR_APPROVAL):
            raise InvalidStateTransitionError(mission.status, MissionStatus.READY_FOR_APPROVAL)

        # Reset failed steps to pending
        for step in mission.plan.steps:
            if step.status == StepStatus.FAILED:
                self.repo.update_step_status(
                    mission_id=mission_id,
                    step_id=step.id,
                    status=StepStatus.PENDING,
                    error_message=None,
                )

        updated = self.repo.update_status(
            session_id=session_id,
            mission_id=mission_id,
            new_status=MissionStatus.READY_FOR_APPROVAL,
            clear_failure_reason=True,
        )
        assert updated is not None
        return updated

    def get_mission_status(self, session_id: str, mission_id: str) -> MissionStatusResponse:
        """Retrieve real-time status and individual step states."""
        mission = self.get_mission(session_id, mission_id)
        is_terminal = mission.status in (MissionStatus.COMPLETED, MissionStatus.CANCELLED)
        step_states = [
            StepStateItem(
                id=s.id,
                title=s.title,
                status=s.status,
                expected_output=s.expected_output,
                error_message=s.error_message,
                completed_at=s.completed_at,
            )
            for s in mission.plan.steps
        ]
        return MissionStatusResponse(
            id=mission.id,
            status=mission.status,
            step_states=step_states,
            is_terminal=is_terminal,
            updated_at=mission.updated_at,
        )

    def list_artifacts(self, session_id: str, mission_id: str) -> ArtifactListResponse:
        """List persistent result artifacts generated for a mission."""
        self.get_mission(session_id, mission_id)
        artifacts = self.repo.list_artifacts(session_id, mission_id)
        return ArtifactListResponse(artifacts=artifacts, total=len(artifacts))

    def get_artifact(self, session_id: str, artifact_id: str) -> tuple[ArtifactItem, str]:
        """Retrieve artifact item metadata and local file path ensuring session isolation."""
        res = self.repo.get_artifact(session_id, artifact_id)
        if not res:
            raise MissionServiceException(
                code="ARTIFACT_NOT_FOUND",
                message=f"Artifact '{artifact_id}' was not found or belongs to another session.",
                status_code=404,
                retryable=False,
            )
        return res
