import 'dart:convert';

// ─────────────────────────────────────────────────────────
// Status enumerations
// ─────────────────────────────────────────────────────────

/// Lifecycle states for a mission.
///
/// Allowed transitions:
///   draft → needsClarification → readyForApproval → approved → running
///   running → completed | failed | cancelled
///   readyForApproval → cancelled
///   failed → readyForApproval  (retry path)
enum MissionStatus {
  /// Goal entered; plan not yet generated.
  draft,

  /// Planner has identified questions that must be answered before planning.
  needsClarification,

  /// Structured plan is generated; awaiting explicit user approval.
  readyForApproval,

  /// User has approved the plan; ready to execute.
  approved,

  /// Active execution is in progress.
  running,

  /// All required steps succeeded and deliverables are available.
  completed,

  /// Execution failed; partial results preserved where present.
  failed,

  /// User or system cancelled before or during execution.
  cancelled,
}

/// Lifecycle states for an individual step.
enum StepStatus {
  /// Not yet started.
  pending,

  /// Currently executing.
  running,

  /// Step finished successfully.
  completed,

  /// Step failed; error is stored on the step.
  failed,

  /// Skipped due to a dependency failure.
  skipped,
}

// ─────────────────────────────────────────────────────────
// Step model
// ─────────────────────────────────────────────────────────

/// A single step in a mission plan.
class MissionStep {
  final String id;

  /// Concise human-readable label shown in the plan view.
  final String title;

  /// Full description of what this step does.
  final String description;

  /// IDs of other steps that must complete before this one starts.
  final List<String> dependsOn;

  /// Expected deliverable or output description.
  final String expectedOutput;

  StepStatus status;

  /// Error message when [status] is [StepStatus.failed].
  String? errorMessage;

  /// Actual output text when [status] is [StepStatus.completed].
  String? resultText;

  /// Completion timestamp.
  DateTime? completedAt;

  MissionStep({
    required this.id,
    required this.title,
    required this.description,
    this.dependsOn = const [],
    this.expectedOutput = '',
    this.status = StepStatus.pending,
    this.errorMessage,
    this.resultText,
    this.completedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dependsOn': dependsOn,
      'expectedOutput': expectedOutput,
      'status': status.name,
      'errorMessage': errorMessage,
      'resultText': resultText,
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory MissionStep.fromMap(Map<String, dynamic> map) {
    return MissionStep(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      dependsOn: (map['dependsOn'] as List<dynamic>?)?.cast<String>() ?? [],
      expectedOutput: (map['expectedOutput'] as String?) ?? '',
      status: StepStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => StepStatus.pending,
      ),
      errorMessage: map['errorMessage'] as String?,
      resultText: map['resultText'] as String?,
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'] as String)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────
// Clarification question model
// ─────────────────────────────────────────────────────────

/// A single clarifying question the planner needs answered.
class ClarificationQuestion {
  final String id;
  final String question;
  String? answer;

  ClarificationQuestion({
    required this.id,
    required this.question,
    this.answer,
  });

  bool get isAnswered => answer != null && answer!.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'question': question,
        'answer': answer,
      };

  factory ClarificationQuestion.fromMap(Map<String, dynamic> map) =>
      ClarificationQuestion(
        id: map['id'] as String,
        question: map['question'] as String,
        answer: map['answer'] as String?,
      );
}

// ─────────────────────────────────────────────────────────
// Mission model
// ─────────────────────────────────────────────────────────

/// A persistent mission in Tusk.ai.
///
/// Each mission is associated with exactly one conversation.
/// Deleting the conversation sets [conversationId] to null but
/// preserves the mission so the user can see what happened.
class Mission {
  final String id;

  /// The free-form goal the user typed.
  final String objective;

  /// Short auto-generated title (first 60 chars of objective, trimmed).
  String title;

  /// ID of the originating conversation (null if conversation was deleted).
  String? conversationId;

  MissionStatus status;

  /// Ordered list of plan steps. Empty until plan is generated.
  final List<MissionStep> steps;

  /// Clarification questions; populated when status is [MissionStatus.needsClarification].
  final List<ClarificationQuestion> clarifications;

  /// High-level summary of results once completed or partially completed.
  String? resultSummary;

  /// Reason for failure or cancellation.
  String? failureReason;

  final DateTime createdAt;
  DateTime updatedAt;

  /// Whether this was approved by the user before running.
  bool approvedByUser;

  Mission({
    required this.id,
    required this.objective,
    required this.title,
    this.conversationId,
    this.status = MissionStatus.draft,
    List<MissionStep>? steps,
    List<ClarificationQuestion>? clarifications,
    this.resultSummary,
    this.failureReason,
    required this.createdAt,
    required this.updatedAt,
    this.approvedByUser = false,
  })  : steps = steps ?? [],
        clarifications = clarifications ?? [];

  // ── State machine ──────────────────────────────────────

  /// Returns true if transitioning to [next] is a valid state machine move.
  bool canTransitionTo(MissionStatus next) {
    switch (status) {
      case MissionStatus.draft:
        return next == MissionStatus.needsClarification ||
            next == MissionStatus.readyForApproval ||
            next == MissionStatus.cancelled;
      case MissionStatus.needsClarification:
        return next == MissionStatus.readyForApproval ||
            next == MissionStatus.cancelled;
      case MissionStatus.readyForApproval:
        return next == MissionStatus.approved || next == MissionStatus.cancelled;
      case MissionStatus.approved:
        return next == MissionStatus.running || next == MissionStatus.cancelled;
      case MissionStatus.running:
        return next == MissionStatus.completed ||
            next == MissionStatus.failed ||
            next == MissionStatus.cancelled;
      case MissionStatus.failed:
        // Allow retry by returning to readyForApproval
        return next == MissionStatus.readyForApproval ||
            next == MissionStatus.cancelled;
      case MissionStatus.completed:
      case MissionStatus.cancelled:
        return false; // terminal states
    }
  }

  /// Transition to [next] if valid. Returns true on success.
  bool transitionTo(MissionStatus next) {
    if (!canTransitionTo(next)) return false;
    status = next;
    updatedAt = DateTime.now();
    return true;
  }

  // ── Computed helpers ────────────────────────────────────

  bool get isTerminal =>
      status == MissionStatus.completed || status == MissionStatus.cancelled;

  bool get hasSteps => steps.isNotEmpty;

  int get completedStepCount =>
      steps.where((s) => s.status == StepStatus.completed).length;

  bool get allStepsCompleted =>
      hasSteps && completedStepCount == steps.length;

  ClarificationQuestion? get nextUnansweredQuestion =>
      clarifications.where((q) => !q.isAnswered).firstOrNull;

  // ── Serialization ───────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'objective': objective,
      'title': title,
      'conversationId': conversationId,
      'status': status.name,
      'steps': steps.map((s) => s.toMap()).toList(),
      'clarifications': clarifications.map((q) => q.toMap()).toList(),
      'resultSummary': resultSummary,
      'failureReason': failureReason,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'approvedByUser': approvedByUser,
    };
  }

  factory Mission.fromMap(Map<String, dynamic> map) {
    return Mission(
      id: map['id'] as String,
      objective: map['objective'] as String,
      title: map['title'] as String,
      conversationId: map['conversationId'] as String?,
      status: MissionStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => MissionStatus.draft,
      ),
      steps: (map['steps'] as List<dynamic>?)
              ?.map((s) => MissionStep.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      clarifications: (map['clarifications'] as List<dynamic>?)
              ?.map((q) => ClarificationQuestion.fromMap(q as Map<String, dynamic>))
              .toList() ??
          [],
      resultSummary: map['resultSummary'] as String?,
      failureReason: map['failureReason'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      approvedByUser: (map['approvedByUser'] as bool?) ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());
  factory Mission.fromJson(String source) =>
      Mission.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
