import logging
import sqlite3
import uuid
from pathlib import Path
from ..config import settings
from ..database.repository import MissionRepository
from ..models.domain import MissionStatus, StepStatus, can_transition
from ..models.schemas import MissionResponse
from .llm_provider import LLMProvider, GeminiProvider
from .tools import get_tool_for_step, DeliverablePackagerTool

logger = logging.getLogger("tusk.execution")


class ExecutionException(Exception):
    pass


class ExecutionEngine:
    """Orchestrates genuine step execution, state transitions, and persistent artifact generation."""

    def __init__(self, conn: sqlite3.Connection, provider: LLMProvider | None = None):
        self.conn = conn
        self.repo = MissionRepository(conn)
        self.provider = provider or GeminiProvider(settings.gemini_api_key, model=settings.gemini_model)

    async def execute_mission(self, session_id: str, mission_id: str) -> MissionResponse:
        """Run all steps for an approved mission and record verified results."""
        mission = self.repo.get_mission_by_id(session_id, mission_id)
        if not mission:
            raise ExecutionException(f"Mission '{mission_id}' not found.")

        # Ensure valid state transition: must be APPROVED (or RUNNING on resume)
        if mission.status != MissionStatus.APPROVED and mission.status != MissionStatus.RUNNING:
            raise ExecutionException(
                f"Cannot execute mission in status '{mission.status.value}'. Must be 'approved'."
            )

        # Transition to RUNNING
        self.repo.update_status(
            session_id=session_id,
            mission_id=mission_id,
            new_status=MissionStatus.RUNNING,
        )

        prior_context: dict[str, str] = {}
        artifacts_created = 0

        # Create mission artifact directory safely
        mission_artifact_dir = settings.absolute_artifacts_dir / mission_id
        mission_artifact_dir.mkdir(parents=True, exist_ok=True)

        for step in mission.plan.steps:
            # Check for cancellation before starting step
            current_state = self.repo.get_mission_by_id(session_id, mission_id)
            if current_state and current_state.status == MissionStatus.CANCELLED:
                logger.info("Execution stopped due to mission cancellation: %s", mission_id)
                return current_state

            # Mark step RUNNING
            self.repo.update_step_status(
                mission_id=mission_id,
                step_id=step.id,
                status=StepStatus.RUNNING,
            )

            try:
                tool = get_tool_for_step(step.title)
                result = await tool.execute(
                    goal=mission.goal,
                    step_title=step.title,
                    step_description=step.description,
                    prior_context=prior_context,
                    provider=self.provider,
                )

                # Persist artifact if tool produced one
                if result.artifact_filename and result.artifact_content:
                    artifact_path = (mission_artifact_dir / result.artifact_filename).resolve()
                    # Security check: Prevent path traversal
                    if not str(artifact_path).startswith(str(settings.absolute_artifacts_dir.resolve())):
                        raise ExecutionException("Security violation: path traversal detected in artifact name.")

                    with open(artifact_path, "w", encoding="utf-8") as f:
                        f.write(result.artifact_content)

                    artifact_id = f"art_{uuid.uuid4().hex[:10]}"
                    self.repo.create_artifact(
                        artifact_id=artifact_id,
                        mission_id=mission_id,
                        step_id=step.id,
                        session_id=session_id,
                        media_type=result.media_type,
                        name=result.artifact_filename,
                        file_path=str(artifact_path),
                        size_bytes=len(result.artifact_content.encode("utf-8")),
                    )
                    artifacts_created += 1

                # Record step success
                self.repo.update_step_status(
                    mission_id=mission_id,
                    step_id=step.id,
                    status=StepStatus.COMPLETED,
                    result_text=result.text_output,
                )
                prior_context[step.title] = result.text_output

            except Exception as e:
                logger.error("Step '%s' failed in mission %s: %s", step.id, mission_id, e)
                self.repo.update_step_status(
                    mission_id=mission_id,
                    step_id=step.id,
                    status=StepStatus.FAILED,
                    error_message=f"Execution error: {str(e)}",
                )
                # Mark mission failed with partial results preserved
                self.repo.update_status(
                    session_id=session_id,
                    mission_id=mission_id,
                    new_status=MissionStatus.FAILED,
                    failure_reason=f"Step '{step.title}' failed during execution: {str(e)}",
                )
                failed_mission = self.repo.get_mission_by_id(session_id, mission_id)
                assert failed_mission is not None
                return failed_mission

        # If no artifact was produced yet, generate final package deliverable
        if artifacts_created == 0 and prior_context:
            packager = DeliverablePackagerTool()
            pkg_result = await packager.execute(
                goal=mission.goal,
                step_title="Final Deliverables Package",
                step_description="Compile all generated content into deliverable document.",
                prior_context=prior_context,
                provider=self.provider,
            )
            if pkg_result.artifact_filename and pkg_result.artifact_content:
                artifact_path = (mission_artifact_dir / pkg_result.artifact_filename).resolve()
                with open(artifact_path, "w", encoding="utf-8") as f:
                    f.write(pkg_result.artifact_content)

                artifact_id = f"art_{uuid.uuid4().hex[:10]}"
                self.repo.create_artifact(
                    artifact_id=artifact_id,
                    mission_id=mission_id,
                    step_id=None,
                    session_id=session_id,
                    media_type=pkg_result.media_type,
                    name=pkg_result.artifact_filename,
                    file_path=str(artifact_path),
                    size_bytes=len(pkg_result.artifact_content.encode("utf-8")),
                )

        # Mark mission COMPLETED with comprehensive summary
        summary = (
            f"Successfully executed all {len(mission.plan.steps)} mission steps. "
            f"Campaign strategy, social media copy, and structured calendar generated and saved to persistent artifacts."
        )
        self.repo.update_status(
            session_id=session_id,
            mission_id=mission_id,
            new_status=MissionStatus.COMPLETED,
            result_summary=summary,
        )

        completed_mission = self.repo.get_mission_by_id(session_id, mission_id)
        assert completed_mission is not None
        return completed_mission
