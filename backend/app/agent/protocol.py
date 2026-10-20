"""Tusk.ai external agent protocol adapter for Fetch.ai / uAgents.

Enables external agents to interact with Tusk.ai missions while strictly reusing
the core MissionService, ExecutionEngine, SQLite persistence, and approval gates.
"""

import logging
from pathlib import Path
import sqlite3
from uagents import Context, Protocol

from ..config import settings
from ..database.connection import get_db_connection
from ..models.domain import MissionStatus
from ..services.mission_service import (
    InvalidStateTransitionError,
    MissionNotFoundError,
    MissionService,
    MissionServiceException,
)
from .messages import (
    AgentErrorMessage,
    ApproveMissionRequest,
    ArtifactContentResponse,
    ArtifactsListResponse,
    CreateMissionRequest,
    ExecuteMissionRequest,
    GetArtifactContentRequest,
    GetMissionStatusRequest,
    ListArtifactsRequest,
    MissionApprovalResponse,
    MissionExecutionResponse,
    MissionPlanResponse,
    MissionStatusResponse,
)

logger = logging.getLogger("tusk.agent.protocol")

tusk_mission_protocol = Protocol(
    name="tusk_mission_protocol",
    version="1.0.0",
)


def resolve_session_id(sender: str) -> str:
    """Map external agent cryptographic address to an isolated session ID."""
    return f"agent:{sender.strip()}"


# ─────────────────────────────────────────────────────────────────────────────
# Handlers
# ─────────────────────────────────────────────────────────────────────────────

@tusk_mission_protocol.on_message(model=CreateMissionRequest, replies={MissionPlanResponse, AgentErrorMessage})
async def handle_create_mission(ctx: Context, sender: str, msg: CreateMissionRequest):
    """Handle external request to create a mission plan."""
    session_id = resolve_session_id(sender)
    clean_goal = msg.goal.strip()
    if not clean_goal:
        await ctx.send(
            sender,
            AgentErrorMessage(
                error_code="INVALID_GOAL",
                message="Mission goal cannot be blank.",
                retryable=False,
            ),
        )
        return

    try:
        with get_db_connection() as conn:
            service = MissionService(conn)
            mission = await service.create_mission(
                session_id=session_id,
                goal=clean_goal,
                context=msg.context,
                client_request_id=msg.client_request_id,
            )

            clarifications = [c.question for c in mission.clarifications] if mission.clarifications else []
            # Steps live under mission.plan.steps (MissionPlanResponse)
            steps = [s.model_dump() for s in mission.plan.steps]

            await ctx.send(
                sender,
                MissionPlanResponse(
                    mission_id=mission.id,
                    title=mission.title,
                    status=mission.status.value,
                    needs_clarification=mission.status == MissionStatus.NEEDS_CLARIFICATION,
                    steps=steps,
                    clarifications=clarifications,
                    created_at=mission.created_at,
                ),
            )
    except Exception as e:
        logger.exception("Failed to create mission via agent protocol: %s", e)
        await ctx.send(
            sender,
            AgentErrorMessage(
                error_code="PLANNING_FAILED",
                message=f"Failed to create mission plan: {str(e)}",
                retryable=True,
            ),
        )


@tusk_mission_protocol.on_message(model=ApproveMissionRequest, replies={MissionApprovalResponse, AgentErrorMessage})
async def handle_approve_mission(ctx: Context, sender: str, msg: ApproveMissionRequest):
    """Handle explicit user/agent approval of a structured mission plan."""
    session_id = resolve_session_id(sender)
    mission_id = msg.mission_id.strip()

    try:
        with get_db_connection() as conn:
            service = MissionService(conn)
            updated = service.approve_mission(session_id=session_id, mission_id=mission_id)
            await ctx.send(
                sender,
                MissionApprovalResponse(
                    mission_id=updated.id,
                    status=updated.status.value,
                    approved=bool(updated.approved_by_user),
                    approved_at=updated.updated_at,
                ),
            )
    except MissionNotFoundError as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=False))
    except InvalidStateTransitionError as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=False))
    except Exception as e:
        logger.exception("Approval failed for mission %s: %s", mission_id, e)
        await ctx.send(sender, AgentErrorMessage(error_code="INTERNAL_ERROR", message=str(e), retryable=False))


@tusk_mission_protocol.on_message(model=ExecuteMissionRequest, replies={MissionExecutionResponse, AgentErrorMessage})
async def handle_execute_mission(ctx: Context, sender: str, msg: ExecuteMissionRequest):
    """Handle execution of an approved mission. Rejects unapproved missions."""
    session_id = resolve_session_id(sender)
    mission_id = msg.mission_id.strip()

    try:
        with get_db_connection() as conn:
            service = MissionService(conn)

            # Strict approval gate check: external callers CANNOT bypass approval
            current = service.get_mission(session_id=session_id, mission_id=mission_id)
            if current.status not in (MissionStatus.APPROVED, MissionStatus.RUNNING):
                await ctx.send(
                    sender,
                    AgentErrorMessage(
                        error_code="APPROVAL_REQUIRED",
                        message=(
                            f"Mission '{mission_id}' requires explicit approval before execution can start. "
                            f"Current status is '{current.status.value}'."
                        ),
                        retryable=False,
                    ),
                )
                return

            completed = await service.execute_mission(session_id=session_id, mission_id=mission_id)
            # Steps live under completed.plan.steps
            steps = [s.model_dump() for s in completed.plan.steps]

            # Count deliverables
            artifacts_res = service.list_artifacts(session_id=session_id, mission_id=mission_id)

            await ctx.send(
                sender,
                MissionExecutionResponse(
                    mission_id=completed.id,
                    status=completed.status.value,
                    summary=completed.result_summary,
                    steps=steps,
                    artifacts_count=artifacts_res.total,
                    updated_at=completed.updated_at,
                ),
            )
    except MissionNotFoundError as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=False))
    except InvalidStateTransitionError as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=False))
    except Exception as e:
        logger.exception("Execution failed for mission %s: %s", mission_id, e)
        await ctx.send(sender, AgentErrorMessage(error_code="EXECUTION_FAILED", message=str(e), retryable=True))


@tusk_mission_protocol.on_message(model=GetMissionStatusRequest, replies={MissionStatusResponse, AgentErrorMessage})
async def handle_get_status(ctx: Context, sender: str, msg: GetMissionStatusRequest):
    """Handle status query for a mission."""
    session_id = resolve_session_id(sender)
    mission_id = msg.mission_id.strip()

    try:
        with get_db_connection() as conn:
            service = MissionService(conn)
            # get_mission_status returns MissionStatusResponse with step_states list
            status_res = service.get_mission_status(session_id=session_id, mission_id=mission_id)

            # Build step counts map from step_states list
            step_counts: dict[str, int] = {}
            for step in status_res.step_states:
                key = step.status.value
                step_counts[key] = step_counts.get(key, 0) + 1

            await ctx.send(
                sender,
                MissionStatusResponse(
                    mission_id=status_res.id,
                    status=status_res.status.value,
                    step_counts=step_counts,
                    updated_at=status_res.updated_at,
                ),
            )
    except MissionNotFoundError as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=False))
    except Exception as e:
        logger.exception("Status query failed for mission %s: %s", mission_id, e)
        await ctx.send(sender, AgentErrorMessage(error_code="INTERNAL_ERROR", message=str(e), retryable=False))


@tusk_mission_protocol.on_message(model=ListArtifactsRequest, replies={ArtifactsListResponse, AgentErrorMessage})
async def handle_list_artifacts(ctx: Context, sender: str, msg: ListArtifactsRequest):
    """Handle request to list generated deliverables for a mission."""
    session_id = resolve_session_id(sender)
    mission_id = msg.mission_id.strip()

    try:
        with get_db_connection() as conn:
            service = MissionService(conn)
            # list_artifacts verifies session ownership internally via get_mission
            res = service.list_artifacts(session_id=session_id, mission_id=mission_id)
            artifacts = [a.model_dump() for a in res.artifacts]
            await ctx.send(
                sender,
                ArtifactsListResponse(
                    mission_id=mission_id,
                    artifacts=artifacts,
                    total=res.total,
                ),
            )
    except MissionNotFoundError as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=False))
    except Exception as e:
        logger.exception("List artifacts failed for mission %s: %s", mission_id, e)
        await ctx.send(sender, AgentErrorMessage(error_code="INTERNAL_ERROR", message=str(e), retryable=False))


@tusk_mission_protocol.on_message(model=GetArtifactContentRequest, replies={ArtifactContentResponse, AgentErrorMessage})
async def handle_get_artifact_content(ctx: Context, sender: str, msg: GetArtifactContentRequest):
    """Handle request to read the plain text content of a generated artifact."""
    session_id = resolve_session_id(sender)
    mission_id = msg.mission_id.strip()
    artifact_id = msg.artifact_id.strip()

    try:
        with get_db_connection() as conn:
            service = MissionService(conn)
            # Verify mission ownership before artifact access
            service.get_mission(session_id=session_id, mission_id=mission_id)
            # get_artifact enforces session isolation
            art, file_path_str = service.get_artifact(
                session_id=session_id,
                artifact_id=artifact_id,
            )

        # Read file safely from configured artifacts directory
        file_path = Path(file_path_str).resolve()
        base_dir = settings.absolute_artifacts_dir.resolve()
        if not str(file_path).startswith(str(base_dir)) or not file_path.is_file():
            raise MissionServiceException(
                code="ARTIFACT_NOT_FOUND",
                message=f"Artifact file not found or inaccessible.",
                status_code=404,
                retryable=False,
            )

        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()

        await ctx.send(
            sender,
            ArtifactContentResponse(
                mission_id=mission_id,
                artifact_id=art.id,
                name=art.name,
                media_type=art.media_type,
                content=content,
            ),
        )
    except MissionNotFoundError as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=False))
    except MissionServiceException as e:
        await ctx.send(sender, AgentErrorMessage(error_code=e.code, message=e.message, retryable=e.retryable))
    except Exception as e:
        logger.exception("Get artifact content failed for artifact %s: %s", artifact_id, e)
        await ctx.send(sender, AgentErrorMessage(error_code="INTERNAL_ERROR", message=str(e), retryable=False))
