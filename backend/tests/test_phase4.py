import asyncio
import json
import pytest
from unittest.mock import AsyncMock, patch
import httpx
from fastapi.testclient import TestClient

from app.config import settings
from app.database.connection import get_db_connection
from app.models.domain import MissionStatus, StepStatus
from app.services.ai_planner import AIPlannerService
from app.services.execution_engine import ExecutionEngine, ExecutionException
from app.services.llm_provider import (
    GeminiProvider,
    ProviderAuthenticationError,
    ProviderConfigurationError,
    ProviderError,
    ProviderRateLimitError,
    ProviderTimeoutError,
)
from app.services.mission_service import MissionService
from app.services.tools import TOOL_REGISTRY, get_tool_for_step


# ── 1. Provider Unit & Error Tests ───────────────────────────────────────────

@pytest.mark.anyio
async def test_provider_missing_key_raises_configuration_error():
    provider = GeminiProvider(api_key=None)
    with pytest.raises(ProviderConfigurationError) as exc_info:
        await provider.generate_content("Hello")
    assert exc_info.value.code == "PROVIDER_NOT_CONFIGURED"
    assert exc_info.value.status_code == 503


@pytest.mark.anyio
async def test_provider_timeout_handling():
    provider = GeminiProvider(api_key="test-key", timeout=0.1, max_retries=0)
    with patch("httpx.AsyncClient.post", side_effect=httpx.TimeoutException("Timeout")):
        with pytest.raises(ProviderTimeoutError) as exc_info:
            await provider.generate_content("Hello")
        assert exc_info.value.code == "PROVIDER_TIMEOUT"
        assert exc_info.value.retryable is True


@pytest.mark.anyio
async def test_provider_rate_limit_handling():
    provider = GeminiProvider(api_key="test-key", max_retries=0)
    mock_resp = httpx.Response(429, json={"error": {"message": "Resource exhausted"}})
    with patch("httpx.AsyncClient.post", return_value=mock_resp):
        with pytest.raises(ProviderRateLimitError) as exc_info:
            await provider.generate_content("Hello")
        assert exc_info.value.code == "PROVIDER_RATE_LIMIT"
        assert exc_info.value.status_code == 429


@pytest.mark.anyio
async def test_provider_auth_error_handling():
    provider = GeminiProvider(api_key="invalid-key", max_retries=0)
    mock_resp = httpx.Response(403, json={"error": {"message": "API key not valid"}})
    with patch("httpx.AsyncClient.post", return_value=mock_resp):
        with pytest.raises(ProviderAuthenticationError) as exc_info:
            await provider.generate_content("Hello")
        assert exc_info.value.code == "PROVIDER_AUTH_ERROR"
        assert exc_info.value.status_code == 401


# ── 2. AI Planner Tests ──────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_ai_planner_structured_output():
    mock_provider = AsyncMock()
    mock_provider.is_configured = True
    mock_plan = {
        "needs_clarification": False,
        "title": "Seattle Artisanal Cafe Launch",
        "steps": [
            {
                "id": "step_1",
                "title": "Audience Analysis",
                "description": "Analyze downtown foot traffic and tech demographic.",
                "tool_kind": "marketing_strategy",
                "expected_output": "Target audience persona brief",
                "depends_on": []
            },
            {
                "id": "step_2",
                "title": "Draft Post Copy",
                "description": "Produce 5 launch captions with promo code.",
                "tool_kind": "copywriter",
                "expected_output": "5 social media posts",
                "depends_on": ["step_1"]
            }
        ]
    }
    mock_provider.generate_content.return_value = json.dumps(mock_plan)

    planner = AIPlannerService(mock_provider, model_name="gemini-3.8-flash")
    result = await planner.plan("mission_100", "Launch marketing for my cafe in Seattle")

    assert result.needs_clarification is False
    assert result.title == "Seattle Artisanal Cafe Launch"
    assert len(result.steps) == 2
    assert result.steps[0]["id"] == "mission_100_step_1"
    assert result.steps[1]["depends_on"] == ["mission_100_step_1"]
    assert result.planner_mode == "gemini-3.8-flash"


@pytest.mark.anyio
async def test_ai_planner_clarification_on_vague_goal():
    mock_provider = AsyncMock()
    mock_provider.is_configured = True
    mock_clarification = {
        "needs_clarification": True,
        "title": "Campaign Clarification",
        "clarification_question": "What product or café location are you promoting?"
    }
    mock_provider.generate_content.return_value = json.dumps(mock_clarification)

    planner = AIPlannerService(mock_provider)
    result = await planner.plan("mission_vague", "marketing campaign")

    assert result.needs_clarification is True
    assert len(result.clarifications) == 1
    assert result.clarifications[0]["question"] == "What product or café location are you promoting?"
    assert len(result.steps) == 0


@pytest.mark.anyio
async def test_ai_planner_malformed_json_fallback():
    mock_provider = AsyncMock()
    mock_provider.is_configured = True
    mock_provider.generate_content.return_value = "Not valid json"

    planner = AIPlannerService(mock_provider)
    result = await planner.plan("mission_fb", "Write a marketing launch plan for Seattle café")

    assert result.planner_mode == "development"
    assert len(result.steps) > 0


# ── 3. Tool Registry & Execution Engine Tests ────────────────────────────────

def test_tool_registry_resolution():
    tool1 = get_tool_for_step("Audience Profile Analysis")
    assert tool1.name == "marketing_strategy"

    tool2 = get_tool_for_step("Draft Social Media Copy")
    assert tool2.name == "copywriter"

    tool3 = get_tool_for_step("Build 4-Week Posting Calendar")
    assert tool3.name == "content_planner"

    tool4 = get_tool_for_step("Final Package and Deliverables")
    assert tool4.name == "deliverable_packager"


def test_execution_requires_approval_gate(client: TestClient):
    headers = {"X-Session-ID": "test-session-gate"}
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Launch cafe in Seattle"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]
    assert create_resp.json()["status"] == "readyForApproval"

    # Attempting to execute unapproved mission must fail with 409
    bad_exec = client.post(f"/v1/missions/{mission_id}/execute", headers=headers)
    assert bad_exec.status_code == 409
    assert bad_exec.json()["error"]["code"] == "INVALID_STATE_TRANSITION"


def test_end_to_end_execution_and_artifact_generation(client: TestClient):
    headers = {"X-Session-ID": "test-session-e2e"}
    # 1. Create mission
    create_resp = client.post(
        "/v1/missions",
        json={"goal": "Create a launch campaign for artisanal cafe in downtown Seattle"},
        headers=headers,
    )
    mission_id = create_resp.json()["id"]

    # 2. Approve plan
    appr_resp = client.post(f"/v1/missions/{mission_id}/approve", headers=headers)
    assert appr_resp.status_code == 200
    assert appr_resp.json()["status"] == "approved"
    assert appr_resp.json()["approved_by_user"] is True

    # 3. Execute approved mission
    exec_resp = client.post(f"/v1/missions/{mission_id}/execute", headers=headers)
    assert exec_resp.status_code == 200
    data = exec_resp.json()

    assert data["status"] == "completed"
    assert data["result_summary"] is not None
    assert all(s["status"] == "completed" for s in data["plan"]["steps"])

    # 4. List artifacts
    art_resp = client.get(f"/v1/missions/{mission_id}/artifacts", headers=headers)
    assert art_resp.status_code == 200
    art_data = art_resp.json()
    assert art_data["total"] >= 1
    artifact = art_data["artifacts"][0]
    assert artifact["name"].endswith(".md")
    assert artifact["size_bytes"] > 0

    # 5. Retrieve artifact metadata and download content
    art_id = artifact["id"]
    meta_resp = client.get(f"/v1/artifacts/{art_id}", headers=headers)
    assert meta_resp.status_code == 200
    assert meta_resp.json()["id"] == art_id

    content_resp = client.get(f"/v1/artifacts/{art_id}/content", headers=headers)
    assert content_resp.status_code == 200
    assert "Launch Campaign Deliverables Package" in content_resp.text
    assert len(content_resp.text) > 0


def test_artifact_session_isolation(client: TestClient):
    headers_owner = {"X-Session-ID": "owner-session"}
    headers_intruder = {"X-Session-ID": "intruder-session"}

    # Create and execute as owner
    c_resp = client.post("/v1/missions", json={"goal": "Plan launch"}, headers=headers_owner)
    m_id = c_resp.json()["id"]
    client.post(f"/v1/missions/{m_id}/approve", headers=headers_owner)
    client.post(f"/v1/missions/{m_id}/execute", headers=headers_owner)

    # Get owner's artifact ID
    arts = client.get(f"/v1/missions/{m_id}/artifacts", headers=headers_owner).json()["artifacts"]
    art_id = arts[0]["id"]

    # Intruder tries to list owner's artifacts -> 404
    intruder_list = client.get(f"/v1/missions/{m_id}/artifacts", headers=headers_intruder)
    assert intruder_list.status_code == 404

    # Intruder tries to download owner's artifact -> 404
    intruder_get = client.get(f"/v1/artifacts/{art_id}/content", headers=headers_intruder)
    assert intruder_get.status_code == 404
