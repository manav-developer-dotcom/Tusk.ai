from typing import Any
from pydantic import BaseModel, Field
from .domain import MissionStatus, StepStatus


# ─────────────────────────────────────────────────────────────────────────────
# Request Models
# ─────────────────────────────────────────────────────────────────────────────

class CreateMissionRequest(BaseModel):
    goal: str = Field(..., min_length=1, max_length=2000, description="Natural-language goal")
    context: dict[str, Any] | None = Field(default=None, description="Optional caller context")
    client_request_id: str | None = Field(default=None, max_length=128, description="Idempotency key")


class CancelMissionRequest(BaseModel):
    reason: str | None = Field(default="Cancelled by user.", max_length=500)


# ─────────────────────────────────────────────────────────────────────────────
# Response Models
# ─────────────────────────────────────────────────────────────────────────────

class ClarificationQuestion(BaseModel):
    id: str
    question: str
    answer: str | None = None


class MissionStepResponse(BaseModel):
    id: str
    title: str
    description: str
    depends_on: list[str] = Field(default_factory=list)
    expected_output: str = ""
    status: StepStatus = StepStatus.PENDING
    error_message: str | None = None
    result_text: str | None = None
    completed_at: str | None = None


class MissionPlanResponse(BaseModel):
    version: int = 1
    steps: list[MissionStepResponse] = Field(default_factory=list)


class MissionResponse(BaseModel):
    id: str
    goal: str
    title: str
    status: MissionStatus
    session_id: str
    plan: MissionPlanResponse
    clarifications: list[ClarificationQuestion] = Field(default_factory=list)
    result_summary: str | None = None
    failure_reason: str | None = None
    created_at: str
    updated_at: str
    approved_by_user: bool = False


class MissionListResponse(BaseModel):
    missions: list[MissionResponse]
    total: int


class StepStateItem(BaseModel):
    id: str
    title: str
    status: StepStatus
    expected_output: str = ""
    error_message: str | None = None
    completed_at: str | None = None


class MissionStatusResponse(BaseModel):
    id: str
    status: MissionStatus
    step_states: list[StepStateItem]
    is_terminal: bool
    updated_at: str


class ArtifactItem(BaseModel):
    id: str
    mission_id: str
    step_id: str | None = None
    media_type: str
    name: str
    size_bytes: int | None = None
    url: str | None = None
    created_at: str


class ArtifactListResponse(BaseModel):
    artifacts: list[ArtifactItem] = Field(default_factory=list)
    total: int = 0


# ─────────────────────────────────────────────────────────────────────────────
# Structured Error Models (API_CONTRACT.md)
# ─────────────────────────────────────────────────────────────────────────────

class ErrorDetail(BaseModel):
    code: str
    message: str
    retryable: bool = False
    correlation_id: str | None = None


class ErrorResponse(BaseModel):
    error: ErrorDetail
