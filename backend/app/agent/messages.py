"""Typed message schemas for external agent interoperability via uAgents."""

from typing import Any, Optional
from uagents import Model


class CreateMissionRequest(Model):
    """External request to create a mission plan from a natural-language goal."""
    goal: str
    context: dict[str, Any] = {}
    client_request_id: Optional[str] = None


class MissionStepItem(Model):
    """Representation of an ordered step within a structured mission plan."""
    id: str
    step_order: int
    title: str
    description: str
    expected_output: str
    status: str
    depends_on: list[str] = []
    completed_at: Optional[str] = None
    error_message: Optional[str] = None


class MissionPlanResponse(Model):
    """Response containing the AI-generated or clarification-state mission plan."""
    mission_id: str
    title: str
    status: str
    needs_clarification: bool
    steps: list[dict[str, Any]] = []
    clarifications: list[str] = []
    created_at: str


class ApproveMissionRequest(Model):
    """External request to approve a mission plan, unlocking execution."""
    mission_id: str


class MissionApprovalResponse(Model):
    """Response confirming that a mission was approved."""
    mission_id: str
    status: str
    approved: bool
    approved_at: str


class ExecuteMissionRequest(Model):
    """External request to execute an approved mission with backend tools."""
    mission_id: str


class MissionExecutionResponse(Model):
    """Response containing execution results and deliverable counts."""
    mission_id: str
    status: str
    summary: Optional[str] = None
    steps: list[dict[str, Any]] = []
    artifacts_count: int
    updated_at: str


class GetMissionStatusRequest(Model):
    """Query current status and step progress of a mission."""
    mission_id: str


class MissionStatusResponse(Model):
    """Current mission status and step counter breakdown."""
    mission_id: str
    status: str
    step_counts: dict[str, int]
    updated_at: str


class ListArtifactsRequest(Model):
    """Query deliverables and generated artifacts for a mission."""
    mission_id: str


class ArtifactsListResponse(Model):
    """List of generated artifacts/deliverables."""
    mission_id: str
    artifacts: list[dict[str, Any]]
    total: int


class GetArtifactContentRequest(Model):
    """Query full text content of a specific deliverable artifact."""
    mission_id: str
    artifact_id: str


class ArtifactContentResponse(Model):
    """Full content of a specific deliverable artifact."""
    mission_id: str
    artifact_id: str
    name: str
    media_type: str
    content: str


class AgentErrorMessage(Model):
    """Standardized error message for protocol requests."""
    error_code: str
    message: str
    retryable: bool = False
