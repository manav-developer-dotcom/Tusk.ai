import time
from typing import Any
from ..models.domain import StepStatus


class RuleBasedPlannerService:
    """DEVELOPMENT PLANNER ADAPTER (RULE-BASED).

    This service generates structured plans and clarification questions
    using deterministic pattern-matching. It is a development adapter,
    NOT an AI model connection.

    In Phase 4, this adapter will be augmented or replaced by a real
    LLM provider adapter without changing the external mission contract.
    """

    ADAPTER_NAME = "development_rule_based_planner"

    @staticmethod
    def needs_clarification(goal: str) -> bool:
        """Return True if goal is vague or lacks sufficient detail to plan directly."""
        g = goal.strip().lower()
        if len(g) < 10:
            return True
        vague_terms = ["something", "stuff", "things", "it", "that", "do it"]
        for t in vague_terms:
            if g == t or g.startswith(f"{t} ") or g.endswith(f" {t}"):
                return True
        return False

    @staticmethod
    def generate_clarifications(mission_id: str, goal: str) -> list[dict[str, Any]]:
        """Generate targeted clarification questions for ambiguous goals."""
        ts = int(time.time() * 1000)
        return [
            {
                "id": f"{mission_id}_q1_{ts}",
                "question": "What is the specific desired outcome for this goal?",
                "answer": None,
            },
            {
                "id": f"{mission_id}_q2_{ts}",
                "question": "Is there a specific format or audience for the result?",
                "answer": None,
            },
        ]

    @staticmethod
    def generate_plan(
        mission_id: str, goal: str, clarifications: list[dict[str, Any]] | None = None
    ) -> list[dict[str, Any]]:
        """Generate an ordered list of mission steps based on goal intent."""
        g = goal.strip().lower()
        ts = int(time.time() * 1000)

        writing_terms = [
            "write", "draft", "document", "article", "blog", "post",
            "email", "letter", "report", "summary", "announcement", "note",
        ]
        research_terms = [
            "research", "analyse", "analyze", "compare", "investigate",
            "find", "gather", "collect", "look up", "explore",
        ]
        planning_terms = [
            "plan", "schedule", "organise", "organize", "roadmap",
            "strategy", "outline", "structure", "break down",
        ]

        if any(term in g for term in writing_terms):
            return RuleBasedPlannerService._writing_plan(mission_id, ts)
        if any(term in g for term in research_terms):
            return RuleBasedPlannerService._research_plan(mission_id, ts)
        if any(term in g for term in planning_terms):
            return RuleBasedPlannerService._planning_plan(mission_id, ts)
        return RuleBasedPlannerService._generic_plan(mission_id, ts)

    @staticmethod
    def _writing_plan(mission_id: str, ts: int) -> list[dict[str, Any]]:
        s1 = f"{mission_id}_s1_{ts}"
        s2 = f"{mission_id}_s2_{ts}"
        s3 = f"{mission_id}_s3_{ts}"
        s4 = f"{mission_id}_s4_{ts}"
        return [
            {
                "id": s1,
                "title": "Define scope and audience",
                "description": "Identify who the content is for, key message, tone, length, and constraints.",
                "depends_on": [],
                "expected_output": "Content brief with audience, purpose, and key points.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s2,
                "title": "Create an outline",
                "description": "Structure the main sections or arguments before writing.",
                "depends_on": [s1],
                "expected_output": "Structured outline with section headings.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s3,
                "title": "Write the first draft",
                "description": "Produce a complete first draft following the outline.",
                "depends_on": [s2],
                "expected_output": "Complete draft document ready for review.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s4,
                "title": "Review and refine",
                "description": "Check clarity, accuracy, tone, and correct errors.",
                "depends_on": [s3],
                "expected_output": "Final polished document.",
                "status": StepStatus.PENDING.value,
            },
        ]

    @staticmethod
    def _research_plan(mission_id: str, ts: int) -> list[dict[str, Any]]:
        s1 = f"{mission_id}_s1_{ts}"
        s2 = f"{mission_id}_s2_{ts}"
        s3 = f"{mission_id}_s3_{ts}"
        return [
            {
                "id": s1,
                "title": "Define research questions",
                "description": "Specify the exact questions to answer and sources to use.",
                "depends_on": [],
                "expected_output": "List of research questions and source types.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s2,
                "title": "Gather information",
                "description": "Collect relevant data, facts, and references.",
                "depends_on": [s1],
                "expected_output": "Raw research notes with sources cited.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s3,
                "title": "Synthesise findings",
                "description": "Organise and summarise the key insights into a coherent result.",
                "depends_on": [s2],
                "expected_output": "Summary report of findings.",
                "status": StepStatus.PENDING.value,
            },
        ]

    @staticmethod
    def _planning_plan(mission_id: str, ts: int) -> list[dict[str, Any]]:
        s1 = f"{mission_id}_s1_{ts}"
        s2 = f"{mission_id}_s2_{ts}"
        s3 = f"{mission_id}_s3_{ts}"
        return [
            {
                "id": s1,
                "title": "Clarify goals and constraints",
                "description": "Define objectives, timelines, resources, and constraints.",
                "depends_on": [],
                "expected_output": "Goals and constraints document.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s2,
                "title": "Break down into tasks",
                "description": "Identify and sequence the specific tasks needed to achieve the goal.",
                "depends_on": [s1],
                "expected_output": "Ordered task list with owners and durations.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s3,
                "title": "Build the plan",
                "description": "Assemble tasks into a coherent plan with milestones.",
                "depends_on": [s2],
                "expected_output": "Structured plan ready for review.",
                "status": StepStatus.PENDING.value,
            },
        ]

    @staticmethod
    def _generic_plan(mission_id: str, ts: int) -> list[dict[str, Any]]:
        s1 = f"{mission_id}_s1_{ts}"
        s2 = f"{mission_id}_s2_{ts}"
        s3 = f"{mission_id}_s3_{ts}"
        return [
            {
                "id": s1,
                "title": "Understand the goal",
                "description": "Break down the objective into clear requirements.",
                "depends_on": [],
                "expected_output": "Requirements summary.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s2,
                "title": "Identify actions",
                "description": "List specific actions needed to achieve the goal.",
                "depends_on": [s1],
                "expected_output": "Action list.",
                "status": StepStatus.PENDING.value,
            },
            {
                "id": s3,
                "title": "Produce the result",
                "description": "Execute the actions and compile the output.",
                "depends_on": [s2],
                "expected_output": "Completed deliverable.",
                "status": StepStatus.PENDING.value,
            },
        ]
