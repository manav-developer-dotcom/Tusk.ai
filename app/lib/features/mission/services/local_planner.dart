import '../models/mission.dart';

/// ── LOCAL DEVELOPMENT ADAPTER ──────────────────────────────────────────────
///
/// This planner runs entirely on-device using rule-based logic.
/// It is a DEVELOPMENT ADAPTER — not an AI service connection.
/// It produces structured plans from text patterns so the UX flow
/// can be tested before a real backend is available.
///
/// This class is intentionally isolated here so it can be replaced
/// by a real backend/AI adapter in Phase 3 without touching the UI layer.
///
/// IMPORTANT: Never present output from this class as AI-generated or
/// as having been sent to an external service.
// ─────────────────────────────────────────────────────────────────────────────
class LocalPlannerAdapter {
  const LocalPlannerAdapter();

  /// Returns true if the goal text is specific enough to plan directly,
  /// or false if clarification questions are needed.
  bool needsClarification(String goal) {
    final g = goal.trim().toLowerCase();
    // Goals shorter than 10 chars or that are very vague trigger clarification.
    if (g.length < 10) return true;
    final vagueTerms = ['something', 'stuff', 'things', 'it', 'that', 'do it'];
    for (final t in vagueTerms) {
      if (g == t || g.startsWith('$t ') || g.endsWith(' $t')) return true;
    }
    return false;
  }

  /// Returns a list of clarification questions for the given goal.
  List<ClarificationQuestion> generateClarifications(
      String missionId, String goal) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      ClarificationQuestion(
        id: '${missionId}_q1_$now',
        question: 'What is the specific desired outcome for this goal?',
      ),
      ClarificationQuestion(
        id: '${missionId}_q2_$now',
        question: 'Is there a specific format or audience for the result?',
      ),
    ];
  }

  /// Generates a structured mission plan from the goal text and any
  /// clarification answers. This is purely local rule-based logic.
  ///
  /// Returns a list of [MissionStep]s. The list will always have at least
  /// one step (a research/gather step) and up to four steps.
  List<MissionStep> generatePlan(
      String missionId, String goal, List<ClarificationQuestion> clarifications) {
    final g = goal.trim().toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Identify the goal category from keywords
    final isWriting = _containsAny(g, [
      'write', 'draft', 'document', 'article', 'blog', 'post',
      'email', 'letter', 'report', 'summary', 'announcement', 'note',
    ]);
    final isResearch = _containsAny(g, [
      'research', 'analyse', 'analyze', 'compare', 'investigate',
      'find', 'gather', 'collect', 'look up', 'explore',
    ]);
    final isPlan = _containsAny(g, [
      'plan', 'schedule', 'organise', 'organize', 'roadmap',
      'strategy', 'outline', 'structure', 'break down',
    ]);

    if (isWriting) return _writingPlan(missionId, goal, now);
    if (isResearch) return _researchPlan(missionId, goal, now);
    if (isPlan) return _planningPlan(missionId, goal, now);
    return _genericPlan(missionId, goal, now);
  }

  // ── Plan templates ──────────────────────────────────────────────────────────

  List<MissionStep> _writingPlan(
      String missionId, String goal, int ts) {
    final s1 = '${missionId}_s1_$ts';
    final s2 = '${missionId}_s2_$ts';
    final s3 = '${missionId}_s3_$ts';
    final s4 = '${missionId}_s4_$ts';
    return [
      MissionStep(
        id: s1,
        title: 'Define scope and audience',
        description: 'Identify who the content is for, the key message, '
            'tone, length, and any constraints.',
        expectedOutput: 'Content brief with audience, purpose, and key points.',
      ),
      MissionStep(
        id: s2,
        title: 'Create an outline',
        description: 'Structure the main sections or arguments before writing.',
        dependsOn: [s1],
        expectedOutput: 'Structured outline with section headings.',
      ),
      MissionStep(
        id: s3,
        title: 'Write the first draft',
        description: 'Produce a complete first draft following the outline.',
        dependsOn: [s2],
        expectedOutput: 'Complete draft document ready for review.',
      ),
      MissionStep(
        id: s4,
        title: 'Review and refine',
        description: 'Check clarity, accuracy, tone, and correct errors.',
        dependsOn: [s3],
        expectedOutput: 'Final polished document.',
      ),
    ];
  }

  List<MissionStep> _researchPlan(
      String missionId, String goal, int ts) {
    final s1 = '${missionId}_s1_$ts';
    final s2 = '${missionId}_s2_$ts';
    final s3 = '${missionId}_s3_$ts';
    return [
      MissionStep(
        id: s1,
        title: 'Define research questions',
        description: 'Specify the exact questions to answer and sources to use.',
        expectedOutput: 'List of research questions and source types.',
      ),
      MissionStep(
        id: s2,
        title: 'Gather information',
        description: 'Collect relevant data, facts, and references.',
        dependsOn: [s1],
        expectedOutput: 'Raw research notes with sources cited.',
      ),
      MissionStep(
        id: s3,
        title: 'Synthesise findings',
        description: 'Organise and summarise the key insights into a coherent result.',
        dependsOn: [s2],
        expectedOutput: 'Summary report of findings.',
      ),
    ];
  }

  List<MissionStep> _planningPlan(
      String missionId, String goal, int ts) {
    final s1 = '${missionId}_s1_$ts';
    final s2 = '${missionId}_s2_$ts';
    final s3 = '${missionId}_s3_$ts';
    return [
      MissionStep(
        id: s1,
        title: 'Clarify goals and constraints',
        description: 'Define objectives, timelines, resources, and constraints.',
        expectedOutput: 'Goals and constraints document.',
      ),
      MissionStep(
        id: s2,
        title: 'Break down into tasks',
        description: 'Identify and sequence the specific tasks needed to achieve the goal.',
        dependsOn: [s1],
        expectedOutput: 'Ordered task list with owners and durations.',
      ),
      MissionStep(
        id: s3,
        title: 'Build the plan',
        description: 'Assemble tasks into a coherent plan with milestones.',
        dependsOn: [s2],
        expectedOutput: 'Structured plan ready for review.',
      ),
    ];
  }

  List<MissionStep> _genericPlan(
      String missionId, String goal, int ts) {
    final s1 = '${missionId}_s1_$ts';
    final s2 = '${missionId}_s2_$ts';
    final s3 = '${missionId}_s3_$ts';
    return [
      MissionStep(
        id: s1,
        title: 'Understand the goal',
        description: 'Break down the objective into clear requirements.',
        expectedOutput: 'Requirements summary.',
      ),
      MissionStep(
        id: s2,
        title: 'Identify actions',
        description: 'List specific actions needed to achieve the goal.',
        dependsOn: [s1],
        expectedOutput: 'Action list.',
      ),
      MissionStep(
        id: s3,
        title: 'Produce the result',
        description: 'Execute the actions and compile the output.',
        dependsOn: [s2],
        expectedOutput: 'Completed deliverable.',
      ),
    ];
  }

  bool _containsAny(String text, List<String> terms) {
    return terms.any((t) => text.contains(t));
  }
}
