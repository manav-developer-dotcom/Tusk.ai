"""Unit and integration tests for Agent Chat Protocol (ACP) adapter.

Validates compliance with AgentChatProtocol 0.3.0, ChatMessage handling,
ChatAcknowledgement, session isolation, and full mission workflow execution.
"""

from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from uagents import Context
from uagents_core.contrib.protocols.chat import (
    ChatAcknowledgement,
    ChatMessage,
    EndSessionContent,
    Resource,
    ResourceContent,
    StartSessionContent,
    TextContent,
)

from app.agent.acp import handle_chat_ack, handle_chat_message, tusk_chat_protocol
from app.agent.agent import create_tusk_agent
from app.agent.protocol import resolve_session_id
from app.database.connection import SCHEMA_SQL
from app.models.domain import MissionStatus
from app.services.llm_provider import GeminiProvider


MOCK_PLAN_RESPONSE = {
    "needs_clarification": False,
    "title": "Tusk.ai ACP Launch Strategy",
    "steps": [
        {
            "id": "step_1",
            "title": "Analyze target developers",
            "description": "Examine developer demographics and pain points.",
            "tool_kind": "marketing_strategy",
            "expected_output": "Audience brief",
            "depends_on": [],
        },
        {
            "id": "step_2",
            "title": "Draft launch announcement",
            "description": "Compose developer-first release post.",
            "tool_kind": "copywriter",
            "expected_output": "Announcement copy",
            "depends_on": ["step_1"],
        },
        {
            "id": "step_3",
            "title": "Package deliverables",
            "description": "Format deliverables into documentation.",
            "tool_kind": "deliverable_packager",
            "expected_output": "Package document",
            "depends_on": ["step_2"],
        },
    ],
}

MOCK_CLARIFICATION_RESPONSE = {
    "needs_clarification": True,
    "title": "Clarification Required",
    "clarification_question": "What product features, target users, and timelines should this cover?",
}


async def mock_generate_content(prompt: str, system_instruction=None, response_schema=None, **kwargs) -> str:
    """Deterministic stub for Gemini API during ACP testing."""
    if response_schema:
        if any(v in prompt.lower() for v in ["help me with marketing", "vague", "do it"]):
            return json.dumps(MOCK_CLARIFICATION_RESPONSE)
        return json.dumps(MOCK_PLAN_RESPONSE)

    if "copy" in prompt.lower():
        return "Developer Announcement Copy: Build autonomous action agents with Tusk.ai."
    elif "strategy" in prompt.lower():
        return "Audience: Full-stack developers. Tone: Precise, professional, monochrome."
    return "ACP test step execution output deliverable content."


@pytest.fixture(autouse=True)
def setup_test_env(tmp_path, monkeypatch):
    """Ensure clean isolated SQLite database, artifacts directory, and mocked Gemini."""
    db_file = tmp_path / "test_acp.db"
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
    """Create a mock uAgents Context."""
    return AsyncMock(spec=Context)


def get_sent_messages(ctx: AsyncMock) -> list[tuple[str, any]]:
    """Extract all messages sent via ctx.send."""
    assert ctx.send.await_count >= 1, "ctx.send was never called"
    return [(call[0][0], call[0][1]) for call in ctx.send.call_args_list]


# ─────────────────────────────────────────────────────────────────────────────
# Protocol Specification Tests
# ─────────────────────────────────────────────────────────────────────────────

def test_acp_protocol_metadata():
    """Verify ACP protocol conforms to AgentChatProtocol 0.3.0 specification."""
    assert tusk_chat_protocol.name == "AgentChatProtocol"
    assert tusk_chat_protocol.version == "0.3.0"
    assert tusk_chat_protocol.verify() is True


def test_agent_includes_both_protocols():
    """Verify create_tusk_agent registers both ACP and bespoke mission protocols."""
    agent = create_tusk_agent(name="tusk_test_agent", port=8999)
    protocol_names = [p.name for p in agent.protocols.values()]
    assert "tusk_mission_protocol" in protocol_names
    assert "AgentChatProtocol" in protocol_names


# ─────────────────────────────────────────────────────────────────────────────
# ACP Chat Lifecycle & Message Handling Tests
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_chat_message_sends_acknowledgement():
    """Verify that every ChatMessage immediately receives a ChatAcknowledgement."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    msg_id = uuid4()
    msg = ChatMessage(
        msg_id=msg_id,
        content=[TextContent(text="help")],
    )

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    # First message sent MUST be ChatAcknowledgement with matching msg_id
    recipient, ack = sent[0]
    assert recipient == sender
    assert isinstance(ack, ChatAcknowledgement)
    assert ack.acknowledged_msg_id == msg_id


@pytest.mark.anyio
async def test_start_session_welcome():
    """Verify StartSessionContent receives a welcoming introduction message."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    msg = ChatMessage(content=[StartSessionContent()])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    assert len(sent) == 2
    recipient, chat_reply = sent[1]
    assert recipient == sender
    assert isinstance(chat_reply, ChatMessage)
    reply_text = chat_reply.text()
    assert "Welcome to Tusk.ai" in reply_text
    assert "help" in reply_text.lower()


@pytest.mark.anyio
async def test_end_session_closure():
    """Verify EndSessionContent receives a respectful sign-off."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    msg = ChatMessage(content=[EndSessionContent()])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    recipient, chat_reply = sent[1]
    assert isinstance(chat_reply, ChatMessage)
    assert "Session closed" in chat_reply.text()


@pytest.mark.anyio
async def test_unsupported_content_type():
    """Verify unsupported content (e.g. non-text ResourceContent) returns honest explanation."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    resource = Resource(uri="https://example.com/audio.wav", metadata={"mime_type": "audio/wav", "role": "voice"})
    msg = ChatMessage(content=[ResourceContent(resource_id=uuid4(), resource=resource)])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    recipient, chat_reply = sent[1]
    assert "Unsupported content type" in chat_reply.text()
    assert "ResourceContent" in chat_reply.text()


@pytest.mark.anyio
async def test_empty_message_guidance():
    """Verify whitespace or empty message returns guidance."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    msg = ChatMessage(content=[TextContent(text="   \n  ")])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    recipient, chat_reply = sent[1]
    assert "describe your goal" in chat_reply.text().lower()


@pytest.mark.anyio
async def test_help_command():
    """Verify 'help' command returns available instructions."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    msg = ChatMessage(content=[TextContent(text="help")])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    recipient, chat_reply = sent[1]
    assert "Available Commands" in chat_reply.text()
    assert "approve" in chat_reply.text()
    assert "status" in chat_reply.text()
    assert "artifacts" in chat_reply.text()


# ─────────────────────────────────────────────────────────────────────────────
# Full Mission Workflow Tests via ACP
# ─────────────────────────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_create_mission_plan_via_chat():
    """Verify stating a goal in natural language generates a structured mission plan."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    goal = "Create a developer launch strategy and announcement copy for Tusk.ai"
    msg = ChatMessage(content=[TextContent(text=goal)])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    recipient, chat_reply = sent[1]
    text = chat_reply.text()

    assert "Mission Planned: Tusk.ai ACP Launch Strategy" in text
    assert "Mission ID:" in text
    assert "Ready for Approval" in text
    assert "Execution Plan:" in text
    assert "Analyze target developers" in text
    assert "Reply **approve**" in text


@pytest.mark.anyio
async def test_clarification_flow_via_chat():
    """Verify vague goals return targeted clarification questions."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    msg = ChatMessage(content=[TextContent(text="help me with marketing")])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    recipient, chat_reply = sent[1]
    text = chat_reply.text()

    assert "Clarification Required" in text
    assert "What product features, target users, and timelines" in text


@pytest.mark.anyio
async def test_complete_primary_workflow_plan_approve_execute_artifacts():
    """Verify full end-to-end user workflow: Goal -> Plan -> Approve -> Execute -> Deliverables."""
    sender = "agent1qv_sender_test"

    # Step 1: Create plan
    ctx1 = make_mock_context()
    msg1 = ChatMessage(content=[TextContent(text="Build launch campaign for Tusk.ai")])
    await handle_chat_message(ctx1, sender, msg1)
    plan_text = get_sent_messages(ctx1)[1][1].text()
    assert "Mission Planned" in plan_text
    assert "Ready for Approval" in plan_text

    # Step 2: User says "approve"
    ctx2 = make_mock_context()
    msg2 = ChatMessage(content=[TextContent(text="approve")])
    await handle_chat_message(ctx2, sender, msg2)
    exec_text = get_sent_messages(ctx2)[1][1].text()

    assert "Mission Executed:" in exec_text
    assert "**Status:** Completed" in exec_text
    assert "Generated Deliverables" in exec_text
    assert "deliverable_" in exec_text or "artifact" in exec_text.lower()

    # Step 3: User checks "status"
    ctx3 = make_mock_context()
    msg3 = ChatMessage(content=[TextContent(text="status")])
    await handle_chat_message(ctx3, sender, msg3)
    status_text = get_sent_messages(ctx3)[1][1].text()
    assert "Mission Status:" in status_text
    assert "completed" in status_text.lower()

    # Step 4: User asks for "artifacts"
    ctx4 = make_mock_context()
    msg4 = ChatMessage(content=[TextContent(text="artifacts")])
    await handle_chat_message(ctx4, sender, msg4)
    artifacts_text = get_sent_messages(ctx4)[1][1].text()
    assert "Deliverables for Mission" in artifacts_text

    # Extract an artifact ID from the list
    import re
    match = re.search(r"`(art_[^`]+)`", artifacts_text)
    if match:
        artifact_id = match.group(1)
        # Step 5: User views specific artifact
        ctx5 = make_mock_context()
        msg5 = ChatMessage(content=[TextContent(text=f"artifact {artifact_id}")])
        await handle_chat_message(ctx5, sender, msg5)
        view_text = get_sent_messages(ctx5)[1][1].text()
        assert "Deliverable:" in view_text
        assert artifact_id in view_text


@pytest.mark.anyio
async def test_approve_when_no_pending_mission():
    """Verify approving when no mission is pending returns a clear explanation."""
    ctx = make_mock_context()
    sender = "agent1qv_new_caller"
    msg = ChatMessage(content=[TextContent(text="approve")])

    await handle_chat_message(ctx, sender, msg)

    sent = get_sent_messages(ctx)
    chat_reply = sent[1][1]
    assert "No missions found" in chat_reply.text()


@pytest.mark.anyio
async def test_cancel_mission_via_chat():
    """Verify 'cancel' command aborts the active mission."""
    sender = "agent1qv_cancel_test"

    # Create plan
    ctx1 = make_mock_context()
    msg1 = ChatMessage(content=[TextContent(text="Prepare presentation for stakeholders")])
    await handle_chat_message(ctx1, sender, msg1)

    # Cancel
    ctx2 = make_mock_context()
    msg2 = ChatMessage(content=[TextContent(text="cancel")])
    await handle_chat_message(ctx2, sender, msg2)

    cancel_text = get_sent_messages(ctx2)[1][1].text()
    assert "cancelled" in cancel_text.lower()


@pytest.mark.anyio
async def test_handle_chat_ack_callback():
    """Verify handle_chat_ack executes without error upon receiving external acknowledgement."""
    ctx = make_mock_context()
    sender = "agent1qv_sender_test"
    ack = ChatAcknowledgement(acknowledged_msg_id=uuid4())

    # Should run cleanly and not raise
    await handle_chat_ack(ctx, sender, ack)


@pytest.mark.anyio
async def test_step_failure_honest_reporting_and_partial_deliverables(monkeypatch):
    """Verify partial failure honestly reports Failed status and packages completed step deliverables."""
    from app.services.llm_provider import ProviderUnavailableError

    sender = "agent1qv_failure_test"

    # Step 1: Create plan
    ctx1 = make_mock_context()
    msg1 = ChatMessage(content=[TextContent(text="Draft launch announcement and strategy")])
    await handle_chat_message(ctx1, sender, msg1)
    plan_text = get_sent_messages(ctx1)[1][1].text()
    assert "Ready for Approval" in plan_text

    # Step 2: User says "approve", but step 2 raises ProviderUnavailableError
    async def failing_generate_content(prompt: str, system_instruction=None, response_schema=None, **kwargs) -> str:
        if "step: draft launch announcement" in prompt.lower():
            raise ProviderUnavailableError("The AI model service is currently unavailable. Please retry.")
        return await mock_generate_content(prompt, system_instruction, response_schema, **kwargs)

    with patch.object(GeminiProvider, "generate_content", side_effect=failing_generate_content):
        ctx2 = make_mock_context()
        msg2 = ChatMessage(content=[TextContent(text="approve")])
        await handle_chat_message(ctx2, sender, msg2)
        reply_text = get_sent_messages(ctx2)[1][1].text()

    # Must honestly report Failed and NOT Completed
    assert "**Status:** Failed" in reply_text
    assert "Completed" not in reply_text.split("**Status:**")[1].split("\n")[0]
    assert "Execution Incomplete" in reply_text
    assert "The AI model service is currently unavailable" in reply_text
    assert "[!] Draft launch announcement (failed" in reply_text
    assert "[x] Analyze target developers (completed)" in reply_text
    # Partial deliverables from completed steps must be packaged and available
    assert "Generated Deliverables (1):" in reply_text
    assert "launch_campaign_deliverables.md" in reply_text
    assert "reply **retry** or **approve**" in reply_text


@pytest.mark.anyio
async def test_retry_failed_mission_via_chat():
    """Verify replying 'retry' on a failed mission re-executes steps and completes."""
    from app.services.llm_provider import ProviderUnavailableError

    sender = "agent1qv_retry_flow_test"

    # 1. Plan
    ctx1 = make_mock_context()
    await handle_chat_message(ctx1, sender, ChatMessage(content=[TextContent(text="Create product launch campaign")]))

    # 2. Approve with transient failure on first execution
    should_fail = True
    async def transient_generate_content(prompt: str, system_instruction=None, response_schema=None, **kwargs) -> str:
        if should_fail and ("package" in prompt.lower() or "deliverable" in prompt.lower()):
            raise ProviderUnavailableError("Transient provider outage.")
        return await mock_generate_content(prompt, system_instruction, response_schema, **kwargs)

    with patch.object(GeminiProvider, "generate_content", side_effect=transient_generate_content):
        ctx2 = make_mock_context()
        await handle_chat_message(ctx2, sender, ChatMessage(content=[TextContent(text="approve")]))
        fail_text = get_sent_messages(ctx2)[1][1].text()
        assert "**Status:** Failed" in fail_text

        # 3. Provider recovers; user replies "retry"
        should_fail = False
        ctx3 = make_mock_context()
        await handle_chat_message(ctx3, sender, ChatMessage(content=[TextContent(text="retry")]))
        success_text = get_sent_messages(ctx3)[1][1].text()
        assert "**Status:** Completed" in success_text
        assert "Mission Executed:" in success_text
        assert "Generated Deliverables (" in success_text


@pytest.mark.anyio
async def test_mention_prefix_stripping_routes_commands_and_cleans_goals():
    """Verify @agent1... mention prefixes in chat are stripped for commands and goals."""
    sender = "agent1qv_mention_test"
    mention = "@agent1qdky6r9v9myc024pwk35yq50h0lqcf59jeq9gala6jm8n98jzydwg66t6xg"

    # 1. Mention before 'help' command
    ctx1 = make_mock_context()
    await handle_chat_message(ctx1, sender, ChatMessage(content=[TextContent(text=f"{mention} help")]))
    reply1 = get_sent_messages(ctx1)[1][1].text()
    assert "### Tusk.ai Action Assistant" in reply1
    assert "Available Commands" in reply1

    # 2. Mention before goal creates plan without mention in title
    ctx2 = make_mock_context()
    await handle_chat_message(
        ctx2, sender, ChatMessage(content=[TextContent(text=f"{mention} Create developer launch plan")])
    )
    reply2 = get_sent_messages(ctx2)[1][1].text()
    assert "Mission Planned:" in reply2
    assert mention not in reply2
    assert "Ready for Approval" in reply2

    # 3. Mention before 'approve' command executes rather than creating a new plan
    ctx3 = make_mock_context()
    await handle_chat_message(ctx3, sender, ChatMessage(content=[TextContent(text=f"{mention} approve")]))
    reply3 = get_sent_messages(ctx3)[1][1].text()
    assert "Mission Executed:" in reply3 or "Mission Execution Incomplete:" in reply3
    # Must NOT have created a new plan asking for clarification
    assert "Clarification Required" not in reply3


@pytest.mark.anyio
async def test_prior_completed_steps_preserved_on_retry():
    """Verify that successful prior steps are preserved on retry and NOT re-executed."""
    sender = "agent1qv_preserve_test"
    executed_step_prompts: list[str] = []

    # 1. Plan
    ctx1 = make_mock_context()
    await handle_chat_message(
        ctx1, sender, ChatMessage(content=[TextContent(text="Build developer launch strategy for Tusk.ai")])
    )

    # 2. First attempt: Step 1 succeeds, Step 2 fails with ProviderUnavailableError
    step1_unique_output = "UNIQUE_STRATEGY_OUTPUT_STEP_1"

    async def fail_step_2_generate_content(prompt: str, system_instruction=None, response_schema=None, **kwargs) -> str:
        executed_step_prompts.append(prompt)
        if "draft" in prompt.lower() or "copy" in prompt.lower():
            from app.services.llm_provider import ProviderUnavailableError
            raise ProviderUnavailableError("The AI model service is currently unavailable. Please retry.")
        if "strategy" in prompt.lower() or "analyze" in prompt.lower():
            return step1_unique_output
        return await mock_generate_content(prompt, system_instruction, response_schema, **kwargs)

    with patch.object(GeminiProvider, "generate_content", side_effect=fail_step_2_generate_content):
        ctx2 = make_mock_context()
        await handle_chat_message(ctx2, sender, ChatMessage(content=[TextContent(text="approve")]))
        fail_text = get_sent_messages(ctx2)[1][1].text()

    assert "**Status:** Failed" in fail_text
    assert "[x] Analyze target developers (completed)" in fail_text
    assert "[!] Draft launch announcement (failed" in fail_text

    # Clear prompt recorder to verify what gets executed on retry
    executed_step_prompts.clear()

    # 3. Second attempt (retry): Step 2 recovers.
    # Step 1 MUST NOT be re-executed! Step 2 must receive Step 1's unique output in prior_context!
    async def recover_step_2_generate_content(prompt: str, system_instruction=None, response_schema=None, **kwargs) -> str:
        executed_step_prompts.append(prompt)
        return await mock_generate_content(prompt, system_instruction, response_schema, **kwargs)

    with patch.object(GeminiProvider, "generate_content", side_effect=recover_step_2_generate_content):
        ctx3 = make_mock_context()
        await handle_chat_message(ctx3, sender, ChatMessage(content=[TextContent(text="retry")]))
        success_text = get_sent_messages(ctx3)[1][1].text()

    assert "**Status:** Completed" in success_text
    assert "Mission Executed:" in success_text

    # Verify Step 1 was NEVER re-executed as the active step during the retry
    step1_reexecuted = any("step: analyze target developers" in p.lower() for p in executed_step_prompts)
    assert not step1_reexecuted, "Step 1 was re-executed on retry instead of being preserved!"

    # Verify Step 2 received Step 1's output in prior_context
    step2_prompts = [p for p in executed_step_prompts if "step: draft launch announcement" in p.lower()]
    assert len(step2_prompts) >= 1
    assert step1_unique_output in step2_prompts[0], "Step 2 did not receive Step 1's output in prior_context!"


@pytest.mark.anyio
async def test_failed_or_pending_step_cannot_produce_false_completed_status(tmp_path):
    """Verify that any mission with pending or failed steps strictly refuses to be marked COMPLETED."""
    from app.database.connection import get_db_connection
    from app.database.repository import MissionRepository
    from app.models.domain import MissionStatus, StepStatus
    from app.services.execution_engine import ExecutionEngine
    from app.services.mission_service import MissionService

    with get_db_connection() as conn:
        service = MissionService(conn)
        repo = MissionRepository(conn)
        session_id = "test-strict-completion-session"

        # Create mission
        mission = await service.create_mission(
            session_id=session_id,
            goal="Test strict completion safety",
        )
        service.approve_mission(session_id=session_id, mission_id=mission.id)

        # Execute with Step 2 failing
        async def fail_step_2(prompt: str, **kwargs) -> str:
            if "step: draft launch announcement" in prompt.lower():
                from app.services.llm_provider import ProviderUnavailableError
                raise ProviderUnavailableError("Simulated step failure")
            return "Step success output"

        with patch.object(GeminiProvider, "generate_content", side_effect=fail_step_2):
            engine = ExecutionEngine(conn)
            result = await engine.execute_mission(session_id, mission.id)

        # Result MUST NOT be COMPLETED
        assert result.status != MissionStatus.COMPLETED
        assert result.status == MissionStatus.FAILED

        # Double check fresh DB fetch
        fresh = repo.get_mission_by_id(session_id, mission.id)
        assert fresh.status == MissionStatus.FAILED
        assert fresh.status != MissionStatus.COMPLETED

        # Verify step statuses: Step 1 completed, Step 2 failed, Step 3 pending
        assert fresh.plan.steps[0].status == StepStatus.COMPLETED
        assert fresh.plan.steps[1].status == StepStatus.FAILED
        assert fresh.plan.steps[2].status == StepStatus.PENDING

