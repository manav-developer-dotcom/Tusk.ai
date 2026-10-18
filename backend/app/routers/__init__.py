from .health import router as health_router
from .missions import router as missions_router
from .artifacts import router as artifacts_router

__all__ = ["health_router", "missions_router", "artifacts_router"]
