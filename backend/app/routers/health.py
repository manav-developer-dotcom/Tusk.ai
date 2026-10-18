from datetime import datetime, timezone
from fastapi import APIRouter
from ..database.connection import get_db_connection


router = APIRouter(tags=["Health"])


@router.get("/health", summary="Liveness and readiness check")
def get_health() -> dict[str, str]:
    """Return service health status and verify database connectivity."""
    db_status = "connected"
    try:
        with get_db_connection() as conn:
            conn.execute("SELECT 1;").fetchone()
    except Exception:
        db_status = "unavailable"

    return {
        "status": "healthy" if db_status == "connected" else "degraded",
        "version": "0.1.0",
        "database": db_status,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
