"""Agent Chat Protocol (ACP) adapter for Tusk.ai via uAgents.

Implements the official AgentChatProtocol 0.3.0 from uagents_core, enabling
ASI:One and external agents to interact with Tusk.ai entirely via standard
chat messages, while strictly reusing MissionService, ExecutionEngine,
SQLite persistence, and approval gates.
"""

from datetime import datetime, timezone
import logging
from pathlib import Path
import re
from typing import Optional
from uagents import Context, Protocol
from uagents_core.contrib.protocols.chat import (
    ChatAcknowledgement,
    ChatMessage,
    EndSessionContent,
    StartSessionContent,
    TextContent,
    chat_protocol_spec,
)

from ..config import settings
from ..database.connection import get_db_connection
from ..models.domain import MissionStatus, StepStatus
from ..services.mission_service import (
    InvalidStateTransitionError,
    MissionNotFoundError,
    MissionService,
    MissionServiceException,
)
from .protocol import resolve_session_id

logger = logging.getLogger("tusk.agent.acp")

# Initialize protocol from the official Hackpack specification
tusk_chat_protocol = Protocol(spec=chat_protocol_spec)


def _format_help_message() -> str:
    """Format help text explaining available Tusk.ai commands."""
    return (
        "### Tusk.ai Action Assistant\n\n"
        "State any goal in natural language to generate an actionable execution plan. "
        "Tusk.ai plans the steps, awaits your explicit approval, and executes using autonomous tools.\n\n"
        "**Available Commands:**\n"
        "- **[Goal description]**: Describe any objective to create a new mission plan.\n"
        "- **approve** (or **approve <mission_id>**): Approve and execute the pending mission plan.\n"
        "- **status** (or **status <mission_id>**): Check current progress and step states.\n"
        "- **artifacts**: List all generated deliverables for the active mission.\n"
        "- **artifact <artifact_id>**: Display the full content of a specific deliverable.\n"
        "- **cancel** (or **cancel <mission_id>**): Abort a mission.\n"
        "- **help**: Display this reference guide."
    )


def _format_welcome_message() -> str:
    """Format welcoming message for session initiation."""
    return (
        "### Welcome to Tusk.ai\n\n"
        "I am your autonomous action assistant. State what you would like to achieve, "
        "and I will create a structured execution plan for your review.\n\n"
        "For example: *\"Draft a product launch strategy and announcement copy for Tusk.ai version 1.0\"*.\n\n"
        "Reply **help** at any time for command options."
    )


def _find_target_mission_id(
    service: MissionService, session_id: str, requested_id: Optional[str] = None, require_pending: bool = False
) -> Optional[str]:
    """Find target mission ID from request or session history."""
    if requested_id:
        return requested_id.strip()

    missions, _ = service.repo.list_missions(session_id=session_id, limit=20)
    if not missions:
        return None

    if require_pending:
        for m in missions:
            if m.status in (MissionStatus.READY_FOR_APPROVAL, MissionStatus.APPROVED, MissionStatus.FAILED):
                return m.id
        return None

    # Return the most recently updated mission
    return missions[0].id


async def _handle_approve_intent(service: MissionService, session_id: str, arg: Optional[str]) -> str:
    """Approve and execute a mission upon explicit user confirmation, supporting retries."""
    mission_id = _find_target_mission_id(service, session_id, arg, require_pending=True)
    if not mission_id:
        # Check if any mission exists at all
        missions, _ = service.repo.list_missions(session_id=session_id, limit=5)
        if not missions:
            return "No missions found for this session. State a goal to create a plan."
        latest = missions[0]
        return (
            f"No mission is currently awaiting approval. "
            f"Mission '{latest.id}' is currently '{latest.status.value}'. "
            "State a new goal to plan a mission, or reply **status** to check progress."
        )

    # If the target mission previously failed, reset failed steps through retry_mission
    current = service.get_mission(session_id=session_id, mission_id=mission_id)
    if current.status == MissionStatus.FAILED:
        service.retry_mission(session_id=session_id, mission_id=mission_id)

    # 1. Strict approval transition (if not already approved)
    if current.status != MissionStatus.APPROVED:
        service.approve_mission(session_id=session_id, mission_id=mission_id)

    # 2. Autonomous execution
    completed = await service.execute_mission(session_id=session_id, mission_id=mission_id)

    # 3. Retrieve generated deliverables
    artifacts_res = service.list_artifacts(session_id=session_id, mission_id=mission_id)

    # Format execution response based on actual verified outcome
    # Under NO circumstance can a mission with failed or pending steps be considered a success
    has_failed_steps = any(s.status == StepStatus.FAILED for s in completed.plan.steps)
    has_pending_steps = any(s.status in (StepStatus.PENDING, StepStatus.RUNNING) for s in completed.plan.steps)
    all_steps_completed = len(completed.plan.steps) > 0 and all(
        s.status == StepStatus.COMPLETED for s in completed.plan.steps
    )
    is_success = (
        completed.status == MissionStatus.COMPLETED
        and all_steps_completed
        and not has_failed_steps
        and not has_pending_steps
    )

    if is_success:
        lines = [
            f"### Mission Executed: {completed.title}",
            f"**Mission ID:** `{completed.id}`",
            "**Status:** Completed",
            "",
            "**Summary:**",
            completed.result_summary or "Execution completed successfully.",
            "",
            f"**Steps Completed ({len(completed.plan.steps)}):**",
        ]
        for step in completed.plan.steps:
            lines.append(f"- [x] {step.title} (completed)")
    else:
        status_label = "Failed" if completed.status == MissionStatus.FAILED else completed.status.value.capitalize()
        lines = [
            f"### Mission Execution Incomplete: {completed.title}",
            f"**Mission ID:** `{completed.id}`",
            f"**Status:** {status_label}",
            "",
            "**Issue:**",
            completed.failure_reason or "One or more steps encountered an error during execution.",
            "",
            f"**Step Progress ({len(completed.plan.steps)} steps):**",
        ]
        for step in completed.plan.steps:
            if step.status.value == "completed":
                lines.append(f"- [x] {step.title} (completed)")
            elif step.status.value == "failed":
                err_detail = f" - {step.error_message}" if step.error_message else ""
                lines.append(f"- [!] {step.title} (failed{err_detail})")
            else:
                lines.append(f"- [ ] {step.title} ({step.status.value})")

    lines.append("")
    lines.append(f"**Generated Deliverables ({artifacts_res.total}):**")
    if artifacts_res.artifacts:
        for art in artifacts_res.artifacts:
            lines.append(f"- **{art.name}** (`{art.id}`) | {art.media_type}")
        lines.append("")
        lines.append(f"To view any deliverable, reply with **artifact <id>** (e.g. `artifact {artifacts_res.artifacts[0].id}`).")
    else:
        lines.append("No file deliverables were generated.")

    if not is_success:
        lines.append("")
        lines.append("To retry execution, reply **retry** or **approve**.")

    return "\n".join(lines)


def _handle_status_intent(service: MissionService, session_id: str, arg: Optional[str]) -> str:
    """Retrieve and format real-time mission status."""
    mission_id = _find_target_mission_id(service, session_id, arg, require_pending=False)
    if not mission_id:
        return "No missions found for this session. State a goal to create a plan."

    status_res = service.get_mission_status(session_id=session_id, mission_id=mission_id)
    mission = service.get_mission(session_id=session_id, mission_id=mission_id)

    lines = [
        f"### Mission Status: {mission.title}",
        f"**Mission ID:** `{status_res.id}`",
        f"**Status:** {status_res.status.value}",
        f"**Updated:** {status_res.updated_at}",
        "",
        "**Steps:**",
    ]
    for step in status_res.step_states:
        marker = "[x]" if step.status.value == "completed" else "[ ]"
        lines.append(f"- {marker} {step.title}: {step.status.value}")

    if status_res.status == MissionStatus.READY_FOR_APPROVAL:
        lines.append("")
        lines.append("This mission is awaiting your approval. Reply **approve** to start execution.")

    return "\n".join(lines)


def _handle_artifacts_intent(service: MissionService, session_id: str, arg: Optional[str]) -> str:
    """List deliverables or fetch specific deliverable content."""
    if arg:
        # User specified an artifact ID or mission ID
        target_token = arg.strip()
        # Check if token is an artifact ID
        try:
            art, file_path_str = service.get_artifact(session_id=session_id, artifact_id=target_token)
            file_path = Path(file_path_str).resolve()
            base_dir = settings.absolute_artifacts_dir.resolve()
            if not str(file_path).startswith(str(base_dir)) or not file_path.is_file():
                return f"Artifact file '{target_token}' not found on storage."

            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()

            return (
                f"### Deliverable: {art.name}\n"
                f"**Artifact ID:** `{art.id}`\n"
                f"**Media Type:** {art.media_type}\n"
                f"**Mission ID:** `{art.mission_id}`\n\n"
                f"```\n{content}\n```"
            )
        except MissionServiceException:
            # Maybe the argument is a mission ID; list artifacts for it
            mission_id = target_token
    else:
        mission_id = _find_target_mission_id(service, session_id, require_pending=False)

    if not mission_id:
        return "No missions found for this session."

    artifacts_res = service.list_artifacts(session_id=session_id, mission_id=mission_id)
    if not artifacts_res.artifacts:
        return f"No deliverables found for mission `{mission_id}`."

    lines = [
        f"### Deliverables for Mission `{mission_id}`",
        f"Total deliverables: {artifacts_res.total}",
        "",
    ]
    for art in artifacts_res.artifacts:
        lines.append(f"- **{art.name}** (`{art.id}`) | {art.media_type} ({art.size_bytes} bytes)")

    lines.append("")
    lines.append("To view full content, reply **artifact <id>**.")
    return "\n".join(lines)


def _handle_cancel_intent(service: MissionService, session_id: str, arg: Optional[str]) -> str:
    """Cancel target mission."""
    mission_id = _find_target_mission_id(service, session_id, arg, require_pending=False)
    if not mission_id:
        return "No mission found to cancel."

    cancelled = service.cancel_mission(
        session_id=session_id,
        mission_id=mission_id,
        reason="Cancelled by user via chat.",
    )
    return f"Mission `{cancelled.id}` ({cancelled.title}) has been cancelled."


async def _handle_create_plan_intent(service: MissionService, session_id: str, goal: str) -> str:
    """Create a new mission plan or request clarifications."""
    mission = await service.create_mission(
        session_id=session_id,
        goal=goal,
        context={"channel": "acp_chat"},
    )

    if mission.status == MissionStatus.NEEDS_CLARIFICATION:
        questions = [c.question for c in mission.clarifications] if mission.clarifications else []
        lines = [
            "### Clarification Required",
            "",
            "Before I can build an execution plan, I need a few additional details:",
            "",
        ]
        for q in questions:
            lines.append(f"- {q}")
        lines.append("")
        lines.append("Please reply with more specifics regarding scope, audience, or requirements.")
        return "\n".join(lines)

    lines = [
        f"### Mission Planned: {mission.title}",
        f"**Mission ID:** `{mission.id}`",
        f"**Status:** Ready for Approval",
        "",
        "**Execution Plan:**",
    ]
    for i, step in enumerate(mission.plan.steps, start=1):
        lines.append(f"{i}. **{step.title}**: {step.description}")
        if step.expected_output:
            lines.append(f"   *Expected Output:* {step.expected_output}")

    lines.append("")
    lines.append("---")
    lines.append("Explicit approval is required before execution. Reply **approve** to execute this plan, or **cancel** to abort.")
    return "\n".join(lines)


async def process_chat_text(session_id: str, text: str) -> str:
    """Process incoming chat text and return the assistant response."""
    clean_text = text.strip()
    if not clean_text:
        return "Please describe your goal to create a mission plan, or reply **help** for commands."

    # Strip agent mention prefix if present (e.g. from Agentverse / ASI:One chat "@agent1... approve")
    clean_text = re.sub(r"^@agent1[a-z0-9]+\s*", "", clean_text, flags=re.IGNORECASE).strip()
    clean_text = re.sub(r"^@\S+\s*", "", clean_text).strip()
    if not clean_text:
        return "Please describe your goal to create a mission plan, or reply **help** for commands."

    lower = clean_text.lower()

    # 1. Help
    if lower in ("help", "/help", "commands", "?", "what can you do", "info"):
        return _format_help_message()

    with get_db_connection() as conn:
        service = MissionService(conn)

        try:
            # 2. Approval or Retry
            if (
                lower in ("approve", "yes", "proceed", "confirm", "execute", "run", "retry")
                or lower.startswith("approve ")
                or lower.startswith("execute ")
                or lower.startswith("retry ")
            ):
                parts = clean_text.split(maxsplit=1)
                arg = parts[1].strip() if len(parts) > 1 else None
                return await _handle_approve_intent(service, session_id, arg)

            # 3. Status
            if lower in ("status", "progress") or lower.startswith("status "):
                parts = clean_text.split(maxsplit=1)
                arg = parts[1].strip() if len(parts) > 1 else None
                return _handle_status_intent(service, session_id, arg)

            # 4. Deliverables / Artifacts
            if lower in ("artifacts", "deliverables", "list artifacts") or lower.startswith("artifact ") or lower.startswith("view ") or lower.startswith("deliverable "):
                parts = clean_text.split(maxsplit=1)
                arg = parts[1].strip() if len(parts) > 1 else None
                return _handle_artifacts_intent(service, session_id, arg)

            # 5. Cancel
            if lower in ("cancel", "abort") or lower.startswith("cancel "):
                parts = clean_text.split(maxsplit=1)
                arg = parts[1].strip() if len(parts) > 1 else None
                return _handle_cancel_intent(service, session_id, arg)

            # 6. Default: Create mission plan
            return await _handle_create_plan_intent(service, session_id, clean_text)

        except MissionNotFoundError as e:
            return f"Mission '{e.mission_id}' was not found. Reply **status** to check available missions."
        except InvalidStateTransitionError as e:
            return f"Action unavailable: Cannot transition from '{e.current_status.value}' to '{e.target_status.value}'."
        except MissionServiceException as e:
            return f"Mission error: {e.message}"
        except Exception as e:
            logger.exception("Error processing chat message: %s", e)
            return f"An error occurred while processing your request: {str(e)}"


# ─────────────────────────────────────────────────────────────────────────────
# Message Handlers
# ─────────────────────────────────────────────────────────────────────────────

@tusk_chat_protocol.on_message(model=ChatMessage)
async def handle_chat_message(ctx: Context, sender: str, msg: ChatMessage):
    """Handle incoming ACP chat message from ASI:One or an external agent."""
    # 1. Immediately send acknowledgement per AgentChatProtocol specification
    await ctx.send(
        sender,
        ChatAcknowledgement(acknowledged_msg_id=msg.msg_id),
    )

    session_id = resolve_session_id(sender)

    # 2. Inspect content items
    has_start = False
    has_end = False
    unsupported_types = []
    text_parts = []

    for item in msg.content:
        if isinstance(item, TextContent):
            text_parts.append(item.text)
        elif isinstance(item, StartSessionContent):
            has_start = True
        elif isinstance(item, EndSessionContent):
            has_end = True
        else:
            unsupported_types.append(type(item).__name__)

    combined_text = "".join(text_parts).strip()

    # Session lifecycle handlers
    if has_start and not combined_text:
        await ctx.send(
            sender,
            ChatMessage(content=[TextContent(text=_format_welcome_message())]),
        )
        return

    if has_end and not combined_text:
        await ctx.send(
            sender,
            ChatMessage(
                content=[
                    TextContent(
                        text="Session closed. Thank you for using Tusk.ai. Send a message anytime to start a new mission."
                    )
                ]
            ),
        )
        return

    if unsupported_types and not combined_text:
        await ctx.send(
            sender,
            ChatMessage(
                content=[
                    TextContent(
                        text=(
                            f"Unsupported content type(s) received: {', '.join(unsupported_types)}. "
                            "Tusk.ai currently processes text-based messages. Please submit your request as text."
                        )
                    )
                ]
            ),
        )
        return

    # Process user text request
    response_text = await process_chat_text(session_id, combined_text)

    # Return markdown-formatted response in a ChatMessage
    await ctx.send(
        sender,
        ChatMessage(content=[TextContent(text=response_text)]),
    )


@tusk_chat_protocol.on_message(model=ChatAcknowledgement)
async def handle_chat_ack(ctx: Context, sender: str, msg: ChatAcknowledgement):
    """Handle incoming message acknowledgement from external agent or ASI:One."""
    logger.debug(
        "Chat message %s acknowledged by %s",
        msg.acknowledged_msg_id,
        sender,
    )
