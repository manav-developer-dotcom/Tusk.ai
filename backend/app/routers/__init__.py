from .health import router as health_router
from .missions import router as missions_router
from .artifacts import router as artifacts_router
from .auth import router as auth_router, get_current_user, get_optional_user

__all__ = [
    "health_router",
    "missions_router",
    "artifacts_router",
    "auth_router",
    "get_current_user",
    "get_optional_user",
]

