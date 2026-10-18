"""Convenient entry point to launch the Tusk.ai backend server."""
import uvicorn
from app.config import settings

if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.host,
        port=settings.port,
        reload=True if settings.env == "development" else False,
        log_level=settings.log_level.lower(),
    )
