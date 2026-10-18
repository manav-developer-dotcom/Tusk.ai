import json
import os
import tempfile
from pathlib import Path
from typing import Generator
from unittest.mock import AsyncMock, patch
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.database.connection import init_db
from app.main import app
from app.services.llm_provider import GeminiProvider


MOCK_PLAN_RESPONSE = {
    "needs_clarification": False,
    "title": "Launch Announcement Campaign",
    "steps": [
        {
            "id": "step_1",
            "title": "Define scope and audience",
            "description": "Identify core user segments and communication channels.",
            "tool_kind": "marketing_strategy",
            "expected_output": "Audience brief and key themes",
            "depends_on": []
        },
        {
            "id": "step_2",
            "title": "Draft announcement copy",
            "description": "Write launch post copies and promotional messages.",
            "tool_kind": "copywriter",
            "expected_output": "Set of 5 post captions with promo code",
            "depends_on": ["step_1"]
        },
        {
            "id": "step_3",
            "title": "Create publication calendar",
            "description": "Map out multi-week posting timeline.",
            "tool_kind": "content_planner",
            "expected_output": "Weekly schedule table",
            "depends_on": ["step_2"]
        },
        {
            "id": "step_4",
            "title": "Package final deliverables",
            "description": "Assemble all deliverables into a persistent document.",
            "tool_kind": "deliverable_packager",
            "expected_output": "Markdown deliverable package",
            "depends_on": ["step_3"]
        }
    ]
}

MOCK_CLARIFICATION_RESPONSE = {
    "needs_clarification": True,
    "title": "Clarification Required",
    "clarification_question": "Could you provide details on the specific goal, target audience, and key deliverables?"
}


async def mock_generate_content(prompt: str, system_instruction: str | None = None, response_schema: dict | None = None, **kwargs) -> str:
    # If this is a planning prompt
    if response_schema:
        if "do it" in prompt.lower() or "vague" in prompt.lower() or "marketing campaign" == prompt.strip().lower():
            return json.dumps(MOCK_CLARIFICATION_RESPONSE)
        return json.dumps(MOCK_PLAN_RESPONSE)

    # If this is a tool execution prompt
    if "copy" in prompt.lower():
        return (
            "Campaign Post 1: Exceptional craft coffee is arriving downtown.\n"
            "Campaign Post 2: Single-origin espresso roasted in small batches.\n"
            "Campaign Post 3: Use promo code TUSKLAUNCH for 20% off your first visit."
        )
    elif "strategy" in prompt.lower():
        return "Audience: Downtown urban professionals. Brand Tone: Warm, artisanal, calm. Hashtags: #SeattleCoffee #ArtisanalRoastery"
    elif "calendar" in prompt.lower() or "schedule" in prompt.lower():
        return "Week 1: Teaser phase. Week 2: Grand opening. Week 3: Craft spotlight. Week 4: Weekend tasting."
    return "Verified task execution step output."


@pytest.fixture
def temp_db_path() -> Generator[Path, None, None]:
    """Provide an isolated temporary SQLite database for each test."""
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
        db_file = Path(f.name)

    orig_db = settings.db_path
    settings.db_path = str(db_file)
    init_db(db_file)

    yield db_file

    settings.db_path = orig_db
    if db_file.exists():
        try:
            db_file.unlink()
        except Exception:
            pass


@pytest.fixture
def temp_artifacts_dir() -> Generator[Path, None, None]:
    """Provide an isolated temporary artifacts directory for each test."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        orig = settings.artifacts_dir
        settings.artifacts_dir = tmp_dir
        yield Path(tmp_dir)
        settings.artifacts_dir = orig


@pytest.fixture
def mock_gemini():
    """Mock Gemini generate_content for deterministic testing."""
    with patch.object(GeminiProvider, "generate_content", new_callable=AsyncMock) as mock_gen:
        mock_gen.side_effect = mock_generate_content
        yield mock_gen


@pytest.fixture
def client(temp_db_path: Path, temp_artifacts_dir: Path, mock_gemini) -> Generator[TestClient, None, None]:
    """TestClient configured with isolated SQLite database, artifacts, and mocked Gemini."""
    with TestClient(app) as test_client:
        yield test_client
