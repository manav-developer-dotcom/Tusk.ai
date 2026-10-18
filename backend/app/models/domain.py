from enum import Enum


class MissionStatus(str, Enum):
    """Lifecycle states for a mission in Tusk.ai."""
    DRAFT = "draft"
    NEEDS_CLARIFICATION = "needsClarification"
    READY_FOR_APPROVAL = "readyForApproval"
    APPROVED = "approved"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class StepStatus(str, Enum):
    """Lifecycle states for a mission step."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


def can_transition(current: MissionStatus, target: MissionStatus) -> bool:
    """Validate whether a state transition is legal according to the Tusk.ai state machine."""
    if current == target:
        return True

    allowed_transitions = {
        MissionStatus.DRAFT: {
            MissionStatus.NEEDS_CLARIFICATION,
            MissionStatus.READY_FOR_APPROVAL,
            MissionStatus.CANCELLED,
        },
        MissionStatus.NEEDS_CLARIFICATION: {
            MissionStatus.READY_FOR_APPROVAL,
            MissionStatus.CANCELLED,
        },
        MissionStatus.READY_FOR_APPROVAL: {
            MissionStatus.APPROVED,
            MissionStatus.CANCELLED,
        },
        MissionStatus.APPROVED: {
            MissionStatus.RUNNING,
            MissionStatus.CANCELLED,
        },
        MissionStatus.RUNNING: {
            MissionStatus.COMPLETED,
            MissionStatus.FAILED,
            MissionStatus.CANCELLED,
        },
        MissionStatus.FAILED: {
            MissionStatus.READY_FOR_APPROVAL,  # Retry path
            MissionStatus.CANCELLED,
        },
        MissionStatus.COMPLETED: set(),  # Terminal
        MissionStatus.CANCELLED: set(),  # Terminal
    }

    return target in allowed_transitions.get(current, set())
