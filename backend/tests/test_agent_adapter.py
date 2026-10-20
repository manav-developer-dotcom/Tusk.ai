"""Unit and integration tests for Tusk.ai External Agent Interoperability (uAgents adapter)."""

import json
import sqlite3
import pytest
from unittest.mock import AsyncMock, patch
from uagents import Context

from app.services.llm_provider import GeminiProvider

from app.agent.messages import (
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
from app.agent.protocol import (
    handle_approve_mission,
    handle_create_mission,
    handle_execute_mission,
    handle_get_artifact_content,
    handle_get_status,
    handle_list_artifacts,
    resolve_session_id,
    tusk_mission_protocol,
)
from app.database.connection import SCHEMA_SQL, init_db
from app.models.domain import MissionStatus


MOCK_PLAN_RESPONSE = {
    "needs_clarification": False,
    "title": "Agent Test Mission Plan",
    "steps": [
        {"id": "step_1", "title": "Research and strategy", "description": "Audience analysis.", "tool_kind": "marketing_strategy", "expected_output": "Strategy brief", "depends_on": []},
        {"id": "step_2", "title": "Draft announcement copy", "description": "Write copy.", "tool_kind": "copywriter", "expected_output": "Copy set", "depends_on": ["step_1"]},
        {"id": "step_3", "title": "Create content calendar", "description": "Plan timeline.", "tool_kind": "content_planner", "expected_output": "Calendar", "depends_on": ["step_2"]},
        {"id": "step_4", "title": "Package deliverables", "description": "Compile outputs.", "tool_kind": "deliverable_packager", "expected_output": "Package doc", "depends_on": ["step_3"]},
    ]
}

MOCK_CLARIFICATION_RESPONSE = {
    "needs_clarification": True,
    "title": "Clarification Required",
    "clarification_question": "What product, audience, and goal scope should this cover?"
}


async def mock_generate_content(prompt: str, system_instruction=None, response_schema=None, **kwargs) -> str:
    """Deterministic stub for Gemini generate_content used in agent adapter tests."""
    if response_schema:
        if any(v in prompt.lower() for v in ["help me with marketing", "vague", "do it"]):
            return json.dumps(MOCK_CLARIFICATION_RESPONSE)
        return json.dumps(MOCK_PLAN_RESPONSE)
    # Tool execution prompts
    if "copy" in prompt.lower():
        return "Announcement Copy: Launch Tusk.ai now! Use promo TUSK2026."
    elif "strategy" in prompt.lower():
        return "Audience: Tech-savvy professionals. Tone: Confident, clear."
    elif "calendar" in prompt.lower() or "schedule" in prompt.lower():
        return "Week 1: Teaser. Week 2: Launch. Week 3: Follow-up."
    return "Agent test step execution output."


@pytest.fixture(autouse=True)
def setup_test_db(tmp_path, monkeypatch):
    """Ensure a clean, isolated SQLite database, artifacts directory, and mocked Gemini for every test."""
    db_file = tmp_path / "test_agent.db"
    artifacts_dir = tmp_path / "artifacts"
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    with sqlite3.connect(str(db_file)) as conn:
        conn.executescript(SCHEMA_SQL)
        conn.commit()

    monkeypatch.setattr("app.database.connection.get_db_path", lambda: db_file)
    monkeypatch.setattr("app.config.settings.artifacts_dir", str(artifacts_dir))

    with patch.object(GeminiProvider, "generate_content", new_callable=AsyncMock) as mock_gen:
        mock_gen.side_effect = mock_generate_content
        yield db_file



def make_mock_context() -> AsyncMock:
    """Create a mock uAgents Context for capturing sent messages."""
    ctx = AsyncMock(spec=Context)
    return ctx


def get_sent_message(ctx: AsyncMock, expected_type):
    """Helper to extract and type-assert the message sent via ctx.send."""
    assert ctx.send.await_count >= 1, "ctx.send was never called"
    call_args = ctx.send.call_args[0]
    recipient = call_args[0]
    msg = call_args[1]
    assert isinstance(msg, expected_type), f"Expected {expected_type}, got {type(msg)}: {msg}"
    return recipient, msg


# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

def test_resolve_session_id_mapping():
    """Verify cryptographic address is safely mapped to an isolated session ID."""
    address = "agent1qvsefwr78ypda4nsdwafcne9xfhg9qemq9ludvfxvqscccurcanj65wxet5"
    session_id = resolve_session_id(address)
    assert session_id == f"agent:{address}"


def test_protocol_metadata():
    """Verify protocol name and version meet contract expectations."""
    assert tusk_mission_protocol.name == "tusk_mission_protocol"
    assert tusk_mission_protocol.version == "1.0.0"


@pytest.mark.anyio
async def test_create_mission_blank_goal_rejected():
    """Verify empty or blank goal returns an honest INVALID_GOAL error."""
    ctx = make_mock_context()
    sender = "agent1q_sender_test"

    await handle_create_mission(ctx, sender, CreateMissionRequest(goal="   "))
    recipient, err = get_sent_message(ctx, AgentErrorMessage)
    assert recipient == sender
    assert err.error_code == "INVALID_GOAL"
    assert "blank" in err.message.lower()


@pytest.mark.anyio
async def test_create_mission_specific_goal_generates_plan():
    """Verify a valid specific goal generates a structured plan ready for approval."""
    ctx = make_mock_context()
    sender = "agent1q_sender_test"

    req = CreateMissionRequest(
        goal="Write a launch announcement blog post for Tusk.ai version 1.0",
        context={"channel": "Blog", "tone": "Professional"},
    )
    await handle_create_mission(ctx, sender, req)

    recipient, plan = get_sent_message(ctx, MissionPlanResponse)
    assert recipient == sender
    assert plan.mission_id.startswith("mission_")
    assert plan.status == "readyForApproval"
    assert plan.needs_clarification is False
    assert len(plan.steps) >= 3


@pytest.mark.anyio
async def test_create_mission_vague_goal_requires_clarification():
    """Verify a vague goal transitions into needs_clarification with questions."""
    ctx = make_mock_context()
    sender = "agent1q_sender_test"

    req = CreateMissionRequest(goal="Help me with marketing")
    await handle_create_mission(ctx, sender, req)

    recipient, plan = get_sent_message(ctx, MissionPlanResponse)
    assert recipient == sender
    assert plan.status == "needsClarification"
    assert plan.needs_clarification is True
    assert len(plan.clarifications) >= 1


@pytest.mark.anyio
async def test_approval_gate_enforcement_blocks_unapproved_execution():
    """CRITICAL: External agent cannot bypass the approval gate."""
    ctx = make_mock_context()
    sender = "agent1q_sender_test"

    # 1. Create a planned mission
    req = CreateMissionRequest(goal="Create a customer onboarding checklist")
    await handle_create_mission(ctx, sender, req)
    _, plan = get_sent_message(ctx, MissionPlanResponse)
    mission_id = plan.mission_id

    # 2. Attempt to execute WITHOUT approval
    exec_ctx = make_mock_context()
    await handle_execute_mission(exec_ctx, sender, ExecuteMissionRequest(mission_id=mission_id))

    recipient, err = get_sent_message(exec_ctx, AgentErrorMessage)
    assert recipient == sender
    assert err.error_code == "APPROVAL_REQUIRED"
    assert "requires explicit approval" in err.message


@pytest.mark.anyio
async def test_approve_and_execute_full_workflow():
    """Verify full agent workflow: create -> approve -> execute -> fetch deliverables."""
    ctx = make_mock_context()
    sender = "agent1q_sender_test"

    # 1. Create Mission
    await handle_create_mission(
        ctx,
        sender,
        CreateMissionRequest(goal="Draft a press release for Tusk.ai public launch"),
    )
    _, plan = get_sent_message(ctx, MissionPlanResponse)
    mission_id = plan.mission_id

    # 2. Approve Mission
    appr_ctx = make_mock_context()
    await handle_approve_mission(appr_ctx, sender, ApproveMissionRequest(mission_id=mission_id))
    _, appr_res = get_sent_message(appr_ctx, MissionApprovalResponse)
    assert appr_res.approved is True
    assert appr_res.status == MissionStatus.APPROVED.value

    # 3. Check Status
    status_ctx = make_mock_context()
    await handle_get_status(status_ctx, sender, GetMissionStatusRequest(mission_id=mission_id))
    _, status_res = get_sent_message(status_ctx, MissionStatusResponse)
    assert status_res.status == MissionStatus.APPROVED.value

    # 4. Execute Mission
    exec_ctx = make_mock_context()
    await handle_execute_mission(exec_ctx, sender, ExecuteMissionRequest(mission_id=mission_id))
    _, exec_res = get_sent_message(exec_ctx, MissionExecutionResponse)
    assert exec_res.status == MissionStatus.COMPLETED.value
    assert exec_res.artifacts_count >= 1
    assert len(exec_res.steps) >= 1

    # 5. List Artifacts
    art_ctx = make_mock_context()
    await handle_list_artifacts(art_ctx, sender, ListArtifactsRequest(mission_id=mission_id))
    _, art_res = get_sent_message(art_ctx, ArtifactsListResponse)
    assert art_res.total >= 1
    artifact_id = art_res.artifacts[0]["id"]

    # 6. Retrieve Artifact Plaintext Content
    content_ctx = make_mock_context()
    await handle_get_artifact_content(
        content_ctx,
        sender,
        GetArtifactContentRequest(mission_id=mission_id, artifact_id=artifact_id),
    )
    _, content_res = get_sent_message(content_ctx, ArtifactContentResponse)
    assert content_res.artifact_id == artifact_id
    assert len(content_res.content) > 50


@pytest.mark.anyio
async def test_session_isolation_cross_agent_access_denied():
    """Verify Agent B cannot inspect, approve, or execute missions belonging to Agent A."""
    agent_a = "agent1q_legitimate_owner"
    agent_b = "agent1q_unauthorized_party"

    # Agent A creates a mission
    ctx_a = make_mock_context()
    await handle_create_mission(
        ctx_a,
        agent_a,
        CreateMissionRequest(goal="Prepare internal executive brief"),
    )
    _, plan = get_sent_message(ctx_a, MissionPlanResponse)
    mission_id = plan.mission_id

    # Agent B attempts to approve Agent A's mission
    ctx_b_appr = make_mock_context()
    await handle_approve_mission(ctx_b_appr, agent_b, ApproveMissionRequest(mission_id=mission_id))
    _, err_appr = get_sent_message(ctx_b_appr, AgentErrorMessage)
    assert err_appr.error_code == "MISSION_NOT_FOUND"

    # Agent B attempts to query status of Agent A's mission
    ctx_b_status = make_mock_context()
    await handle_get_status(ctx_b_status, agent_b, GetMissionStatusRequest(mission_id=mission_id))
    _, err_status = get_sent_message(ctx_b_status, AgentErrorMessage)
    assert err_status.error_code == "MISSION_NOT_FOUND"

    # Agent B attempts to execute Agent A's mission
    ctx_b_exec = make_mock_context()
    await handle_execute_mission(ctx_b_exec, agent_b, ExecuteMissionRequest(mission_id=mission_id))
    _, err_exec = get_sent_message(ctx_b_exec, AgentErrorMessage)
    assert err_exec.error_code == "MISSION_NOT_FOUND"


@pytest.mark.anyio
async def test_idempotent_creation_via_client_request_id():
    """Verify repeated requests with identical client_request_id return same mission."""
    ctx1 = make_mock_context()
    ctx2 = make_mock_context()
    sender = "agent1q_sender_test"
    req_id = "agent_req_idempotent_123"

    req = CreateMissionRequest(
        goal="Design quarterly goals framework",
        client_request_id=req_id,
    )
    await handle_create_mission(ctx1, sender, req)
    _, plan1 = get_sent_message(ctx1, MissionPlanResponse)

    await handle_create_mission(ctx2, sender, req)
    _, plan2 = get_sent_message(ctx2, MissionPlanResponse)

    assert plan1.mission_id == plan2.mission_id
    assert plan1.title == plan2.title
