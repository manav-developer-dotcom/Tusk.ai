from typing import Annotated
from fastapi import APIRouter, Depends, Header, Query, status
from ..database.connection import get_db_connection
from ..models.schemas import (
    ArtifactListResponse,
    CancelMissionRequest,
    CreateMissionRequest,
    MissionListResponse,
    MissionResponse,
    MissionStatusResponse,
)
from ..services.mission_service import MissionService


router = APIRouter(prefix="/v1/missions", tags=["Missions"])


def get_current_session_id(
    x_session_id: Annotated[str | None, Header(description="Caller anonymous session UUID")] = None,
    session_id: Annotated[str | None, Query(description="Fallback query param for session ID")] = None,
) -> str:
    """Extract or establish session identity ensuring data boundary isolation."""
    sid = x_session_id or session_id
    if not sid or not sid.strip():
        return "guest-default-session"
    return sid.strip()


@router.post("", response_model=MissionResponse, status_code=status.HTTP_201_CREATED, summary="Create a new mission")
def create_mission(
    payload: CreateMissionRequest,
    session_id: str = Depends(get_current_session_id),
) -> MissionResponse:
    """Create a mission from a user goal and automatically generate a plan or clarifications."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        return svc.create_mission(
            session_id=session_id,
            goal=payload.goal,
            context=payload.context,
            client_request_id=payload.client_request_id,
        )


@router.get("", response_model=MissionListResponse, summary="List missions for active session")
def list_missions(
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    session_id: str = Depends(get_current_session_id),
) -> MissionListResponse:
    """Retrieve all missions created by the requesting session."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        return svc.list_missions(session_id=session_id, limit=limit, offset=offset)


@router.get("/{mission_id}", response_model=MissionResponse, summary="Retrieve a mission and its plan")
def get_mission(
    mission_id: str,
    session_id: str = Depends(get_current_session_id),
) -> MissionResponse:
    """Retrieve mission details and full plan steps."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        return svc.get_mission(session_id=session_id, mission_id=mission_id)


@router.post("/{mission_id}/approve", response_model=MissionResponse, summary="Approve mission plan")
def approve_mission(
    mission_id: str,
    session_id: str = Depends(get_current_session_id),
) -> MissionResponse:
    """User approves the generated plan, transitioning the mission to approved."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        return svc.approve_mission(session_id=session_id, mission_id=mission_id)


@router.post("/{mission_id}/cancel", response_model=MissionResponse, summary="Cancel an active mission")
def cancel_mission(
    mission_id: str,
    payload: CancelMissionRequest | None = None,
    session_id: str = Depends(get_current_session_id),
) -> MissionResponse:
    """Request safe mission cancellation."""
    reason = payload.reason if payload and payload.reason else "Cancelled by user."
    with get_db_connection() as conn:
        svc = MissionService(conn)
        return svc.cancel_mission(session_id=session_id, mission_id=mission_id, reason=reason)


@router.post("/{mission_id}/retry", response_model=MissionResponse, summary="Retry a failed mission")
def retry_mission(
    mission_id: str,
    session_id: str = Depends(get_current_session_id),
) -> MissionResponse:
    """Retry eligible failed mission steps by returning state to readyForApproval."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        return svc.retry_mission(session_id=session_id, mission_id=mission_id)


@router.get("/{mission_id}/status", response_model=MissionStatusResponse, summary="Get authoritative status")
def get_mission_status(
    mission_id: str,
    session_id: str = Depends(get_current_session_id),
) -> MissionStatusResponse:
    """Retrieve authoritative mission lifecycle status and individual step states."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        return svc.get_mission_status(session_id=session_id, mission_id=mission_id)


@router.get("/{mission_id}/artifacts", response_model=ArtifactListResponse, summary="List mission artifacts")
def list_mission_artifacts(
    mission_id: str,
    session_id: str = Depends(get_current_session_id),
) -> ArtifactListResponse:
    """List result artifacts. Returns an empty collection in Phase 3 until Phase 4 tools are wired."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        # Ensure mission exists and belongs to the session
        svc.get_mission(session_id=session_id, mission_id=mission_id)
        return ArtifactListResponse(artifacts=[], total=0)
