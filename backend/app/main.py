import logging
import uuid
from contextlib import asynccontextmanager
from typing import AsyncGenerator
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import settings
from .database.connection import init_db
from .routers import artifacts_router, health_router, missions_router
from .services.llm_provider import ProviderError
from .services.mission_service import MissionServiceException


logger = logging.getLogger("tusk.backend")
logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO))


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Startup and shutdown lifecycle management."""
    logger.info("Initializing Tusk.ai backend database...")
    init_db()
    logger.info("Database schema initialized successfully.")
    yield
    logger.info("Shutting down Tusk.ai backend.")


app = FastAPI(
    title="Tusk.ai Mission Service",
    description="Backend mission application service for planning, approval, and task coordination.",
    version="0.1.0",
    lifespan=lifespan,
)

# ── CORS Middleware ──────────────────────────────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Correlation ID Middleware ────────────────────────────────────────────────
@app.middleware("http")
async def correlation_id_middleware(request: Request, call_next):
    correlation_id = request.headers.get("x-correlation-id") or f"req_{uuid.uuid4().hex[:12]}"
    request.state.correlation_id = correlation_id
    response = await call_next(request)
    response.headers["x-correlation-id"] = correlation_id
    return response


# ── Structured Exception Handlers (API_CONTRACT.md) ─────────────────────────
@app.exception_handler(MissionServiceException)
async def mission_service_exception_handler(request: Request, exc: MissionServiceException):
    correlation_id = getattr(request.state, "correlation_id", None)
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
                "retryable": exc.retryable,
                "correlation_id": correlation_id,
            }
        },
    )


@app.exception_handler(ProviderError)
async def provider_error_handler(request: Request, exc: ProviderError):
    correlation_id = getattr(request.state, "correlation_id", None)
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
                "retryable": exc.retryable,
                "correlation_id": correlation_id,
            }
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    correlation_id = getattr(request.state, "correlation_id", None)
    # Extract clean human-readable error messages without internal stack traces
    errors = exc.errors()
    msg = "; ".join([f"{'.'.join(str(loc) for loc in e['loc'])}: {e['msg']}" for e in errors])
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "VALIDATION_ERROR",
                "message": f"Invalid request payload: {msg}",
                "retryable": False,
                "correlation_id": correlation_id,
            }
        },
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    correlation_id = getattr(request.state, "correlation_id", None)
    logger.exception("Unhandled server error [correlation_id=%s]: %s", correlation_id, exc)
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_SERVER_ERROR",
                "message": "An internal server error occurred. Please retry shortly.",
                "retryable": True,
                "correlation_id": correlation_id,
            }
        },
    )


# ── Include Routers ──────────────────────────────────────────────────────────
app.include_router(health_router)
app.include_router(missions_router)
app.include_router(artifacts_router)

