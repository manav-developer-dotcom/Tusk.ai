import os
from pathlib import Path
from typing import Annotated
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Response, status
from ..config import settings
from ..database.connection import get_db_connection
from ..models.schemas import ArtifactItem
from ..services.mission_service import MissionService
from .missions import get_current_session_id

router = APIRouter(prefix="/v1/artifacts", tags=["Artifacts"])


@router.get("/{artifact_id}", response_model=ArtifactItem, summary="Get artifact metadata")
def get_artifact_metadata(
    artifact_id: str,
    session_id: str = Depends(get_current_session_id),
) -> ArtifactItem:
    """Retrieve metadata for a specific deliverable artifact within caller session."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        item, _ = svc.get_artifact(session_id=session_id, artifact_id=artifact_id)
        return item


@router.get("/{artifact_id}/content", summary="Download artifact content")
def get_artifact_content(
    artifact_id: str,
    session_id: str = Depends(get_current_session_id),
) -> Response:
    """Retrieve the raw content of a generated artifact deliverable."""
    with get_db_connection() as conn:
        svc = MissionService(conn)
        item, file_path_str = svc.get_artifact(session_id=session_id, artifact_id=artifact_id)

    file_path = Path(file_path_str).resolve()
    # Security check: Ensure file path is within artifacts directory
    base_dir = settings.absolute_artifacts_dir.resolve()
    if not str(file_path).startswith(str(base_dir)) or not file_path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Artifact deliverable file not found or inaccessible.",
        )

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    return Response(
        content=content,
        media_type=item.media_type or "text/markdown",
        headers={
            "Content-Disposition": f'inline; filename="{item.name}"'
        }
    )
