import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/tusk_theme.dart';
import '../conversation/models/conversation.dart';
import '../mission/models/mission.dart';
import '../mission/services/mission_repository.dart';
import '../mission/services/local_planner.dart';
import '../mission/mission_detail_screen.dart';

/// Primary Home screen for Tusk.ai.
///
/// Mission flow (Phase 4):
///   1. User types a goal → mission sent to backend AI planner
///   2. If clarification needed → one question shown inline
///   3. Once clarified → Gemini-generated plan shown for review
///   4. Mission transitions to [MissionStatus.readyForApproval]
///   5. User taps "Review plan" → [MissionDetailScreen] with approve/cancel/execute
///   6. User approves → taps "Execute Mission" → backend runs real tools
///   7. Completed missions show artifact deliverables
///
/// When no backend is reachable, falls back to local dev adapter with clear label.
class HomeScreen extends StatefulWidget {
  final Conversation? activeConversation;
  final VoidCallback onOpenSidebar;
  final ValueChanged<String> onSubmitGoal;
  final MissionRepository? missionRepository;

  const HomeScreen({
    super.key,
    this.activeConversation,
    required this.onOpenSidebar,
    required this.onSubmitGoal,
    this.missionRepository,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final _planner = const LocalPlannerAdapter();

  /// The active mission for the current conversation, if any.
  Mission? _activeMission;

  /// True while a plan is being generated (local, but we show an honest state).
  bool _isPlanning = false;

  final List<String> _exampleMissions = [
    'Draft a release announcement for our beta version',
    'Summarise market research notes into action items',
    'Structure a weekly product sprint plan',
    'Write a clear project requirements document',
  ];

  @override
  void initState() {
    super.initState();
    _loadMissionForConversation();
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.activeConversation?.id != widget.activeConversation?.id) {
      _loadMissionForConversation();
    }
  }

  void _loadMissionForConversation() {
    final convId = widget.activeConversation?.id;
    if (convId == null || widget.missionRepository == null) {
      setState(() => _activeMission = null);
      return;
    }
    final missions =
        widget.missionRepository!.missionsForConversation(convId);
    setState(() {
      _activeMission = missions.isNotEmpty ? missions.first : null;
    });
  }

  @override
  void dispose() {
    _composerController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onMicTapped() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Voice input requires platform speech APIs — available in a future phase.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // ── Goal submission ────────────────────────────────────────────────────────

  Future<void> _handleSubmit() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;

    // If we are in clarification mode, treat input as an answer
    final mission = _activeMission;
    if (mission != null &&
        mission.status == MissionStatus.needsClarification) {
      await _answerClarification(mission, text);
      return;
    }

    // Otherwise, treat as a new goal
    _composerController.clear();
    _composerFocus.unfocus();

    // Post user message to conversation layer
    widget.onSubmitGoal(text);

    await _startMission(text);
  }

  Future<void> _startMission(String goal) async {
    if (widget.missionRepository == null) return;

    if (widget.missionRepository!.hasRemoteBackend) {
      setState(() => _isPlanning = true);
      try {
        final mission = await widget.missionRepository!.createRemoteMission(
          goal: goal,
          conversationId: widget.activeConversation?.id,
        );
        if (!mounted) return;
        setState(() {
          _activeMission = mission;
          _isPlanning = false;
        });

        if (mission.status == MissionStatus.needsClarification) {
          _postSystemMessage(
              'To plan this mission, I need a little more information. '
              'Please answer the question below.');
        } else {
          _postSystemMessage(
              'Plan ready for your review. Tap "Review plan" to approve or cancel.');
        }
        return;
      } catch (e) {
        if (!mounted) return;
        _postSystemMessage(
            'Backend connection issue ($e). Operating in local offline mode.');
      }
    }

    final now = DateTime.now();
    final missionId = 'mission_${now.millisecondsSinceEpoch}';
    final shortTitle =
        goal.length > 60 ? '${goal.substring(0, 60)}...' : goal;

    final mission = Mission(
      id: missionId,
      objective: goal,
      title: shortTitle,
      conversationId: widget.activeConversation?.id,
      createdAt: now,
      updatedAt: now,
    );

    if (_planner.needsClarification(goal)) {
      // Add clarification questions; transition to needsClarification
      mission.clarifications
          .addAll(_planner.generateClarifications(missionId, goal));
      mission.transitionTo(MissionStatus.needsClarification);
    }

    await widget.missionRepository!.saveMission(mission);
    setState(() => _activeMission = mission);

    if (mission.status == MissionStatus.needsClarification) {
      _postSystemMessage(
          'To plan this mission, I need a little more information. '
          'Please answer the question below.');
    } else {
      await _generatePlan(mission);
    }
  }

  Future<void> _answerClarification(Mission mission, String answer) async {
    final q = mission.nextUnansweredQuestion;
    if (q == null) return;

    _composerController.clear();
    _composerFocus.unfocus();

    q.answer = answer;
    widget.onSubmitGoal(answer); // Record the answer in conversation
    mission.updatedAt = DateTime.now();
    await widget.missionRepository!.saveMission(mission);

    // Check if more questions remain
    final next = mission.nextUnansweredQuestion;
    if (next != null) {
      setState(() => _activeMission = mission);
      _postSystemMessage('');
    } else {
      // All answered — generate plan
      await _generatePlan(mission);
    }
  }

  Future<void> _generatePlan(Mission mission) async {
    setState(() => _isPlanning = true);

    // Simulate a brief local processing moment (honest — this is local work)
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    final steps = _planner.generatePlan(
        mission.id, mission.objective, mission.clarifications);
    mission.steps.addAll(steps);
    mission.transitionTo(MissionStatus.readyForApproval);
    await widget.missionRepository!.saveMission(mission);

    _postSystemMessage(
        'Plan ready for your review. Tap "Review plan" to approve or cancel.');

    setState(() {
      _activeMission = mission;
      _isPlanning = false;
    });
  }

  void _postSystemMessage(String text) {
    if (text.isEmpty) return;
    widget.onSubmitGoal('__system__$text'); // handled in main.dart
  }

  // ── Mission actions ────────────────────────────────────────────────────────

  void _openMissionDetail(Mission mission) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionDetailScreen(
          mission: mission,
          onApprove: () => _approveMission(mission),
          onCancel: () => _cancelMission(mission),
          onRetry: () => _retryMission(mission),
          onExecute: () => _executeMission(mission),
          onDownloadArtifact: widget.missionRepository != null
              ? (id) => widget.missionRepository!.getArtifactContent(id)
              : null,
        ),
      ),
    ).then((_) => _loadMissionForConversation());
  }

  Future<void> _approveMission(Mission mission) async {
    final ok = await widget.missionRepository!.approveMission(mission.id);
    if (ok && mounted) {
      Navigator.pop(context);
      _postSystemMessage(
          'Plan approved. Open the mission and tap "Execute Mission" to run it.');
      _loadMissionForConversation();
    }
  }

  Future<void> _executeMission(Mission mission) async {
    if (widget.missionRepository == null) return;
    Navigator.pop(context);
    _postSystemMessage('Executing mission — running AI-powered steps...');
    _loadMissionForConversation();
    try {
      final updated = await widget.missionRepository!.executeMission(mission.id);
      if (!mounted) return;
      if (updated != null) {
        setState(() => _activeMission = updated);
        if (updated.status == MissionStatus.completed) {
          final count = updated.artifacts.length;
          _postSystemMessage(
              'Mission complete. $count deliverable${count == 1 ? '' : 's'} ready — tap the mission to view them.');
        } else if (updated.status == MissionStatus.failed) {
          _postSystemMessage(
              'Mission encountered an error. Open the mission for details and retry options.');
        } else {
          _postSystemMessage('Mission execution finished.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      _postSystemMessage(
          'Could not reach the backend to execute the mission. Check your connection and retry.');
    }
    _loadMissionForConversation();
  }

  Future<void> _cancelMission(Mission mission) async {
    await widget.missionRepository!.updateStatus(
      mission.id,
      MissionStatus.cancelled,
      failureReason: 'Cancelled by user.',
    );
    if (mounted) {
      Navigator.pop(context);
      _postSystemMessage('Mission cancelled.');
      _loadMissionForConversation();
    }
  }

  Future<void> _retryMission(Mission mission) async {
    // Retry: clear failure and return to readyForApproval
    await widget.missionRepository!.updateStatus(
      mission.id,
      MissionStatus.readyForApproval,
    );
    if (mounted) {
      _loadMissionForConversation();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary =
        isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final cardBg = isDark ? TuskColors.darkSurface : TuskColors.lightSurface;
    final cardBorder = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;
    final dividerColor =
        isDark ? TuskColors.darkDivider : TuskColors.lightDivider;

    final conv = widget.activeConversation;
    final hasMessages = conv != null && conv.messages.isNotEmpty;
    final mission = _activeMission;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('home_sidebar_button'),
          icon: const Icon(LucideIcons.menu, size: 20),
          tooltip: 'Open conversations',
          onPressed: widget.onOpenSidebar,
        ),
        title: Text(
          conv?.title ?? 'Tusk.ai',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (mission != null &&
              mission.status != MissionStatus.cancelled)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: GestureDetector(
                onTap: () => _openMissionDetail(mission),
                child: _MissionChip(status: mission.status),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: hasMessages
                  ? _MessageList(
                      conversation: conv,
                      mission: mission,
                      isDark: isDark,
                      textPrimary: textPrimary,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      onMissionTap: mission != null
                          ? () => _openMissionDetail(mission)
                          : null,
                    )
                  : _EmptyState(
                      examples: _exampleMissions,
                      composerController: _composerController,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      cardBg: cardBg,
                      cardBorder: cardBorder,
                      isDark: isDark,
                    ),
            ),

            // ── Clarification question prompt ──────────────────────────
            if (mission != null &&
                mission.status == MissionStatus.needsClarification &&
                mission.nextUnansweredQuestion != null)
              _ClarificationBanner(
                question: mission.nextUnansweredQuestion!.question,
                isDark: isDark,
                cardBg: cardBg,
                cardBorder: cardBorder,
                textSecondary: textSecondary,
              ),

            // ── Planning indicator ─────────────────────────────────────
            if (_isPlanning)
              _PlanningIndicator(
                isDark: isDark,
                textSecondary: textSecondary,
                usingRemote: widget.missionRepository?.hasRemoteBackend ?? false,
              ),

            // ── Plan-ready action strip ────────────────────────────────
            if (mission != null &&
                (mission.status == MissionStatus.readyForApproval ||
                 mission.status == MissionStatus.approved))
              _PlanReadyStrip(
                isDark: isDark,
                status: mission.status,
                onReview: () => _openMissionDetail(mission),
                textPrimary: textPrimary,
                cardBg: cardBg,
                cardBorder: cardBorder,
              ),

            // ── Composer ───────────────────────────────────────────────
            _Composer(
              controller: _composerController,
              focusNode: _composerFocus,
              onMicTapped: _onMicTapped,
              onSubmit: _handleSubmit,
              isDark: isDark,
              textSecondary: textSecondary,
              cardBg: cardBg,
              dividerColor: dividerColor,
              hintText: _composerHint(mission),
            ),
          ],
        ),
      ),
    );
  }

  String _composerHint(Mission? mission) {
    if (mission == null) return 'Describe an outcome or project...';
    if (mission.status == MissionStatus.needsClarification) {
      return 'Answer the question above...';
    }
    return 'Describe an outcome or project...';
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final Conversation conversation;
  final Mission? mission;
  final bool isDark;
  final Color textPrimary;
  final Color cardBg;
  final Color cardBorder;
  final VoidCallback? onMissionTap;

  const _MessageList({
    required this.conversation,
    required this.mission,
    required this.isDark,
    required this.textPrimary,
    required this.cardBg,
    required this.cardBorder,
    this.onMissionTap,
  });

  @override
  Widget build(BuildContext context) {
    final visibleMessages = conversation.messages
        .where((m) => !m.text.startsWith('__system__'))
        .toList();

    final systemMessages = conversation.messages
        .where((m) => m.text.startsWith('__system__'))
        .map((m) => m.text.substring('__system__'.length))
        .where((t) => t.isNotEmpty)
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      children: [
        ...visibleMessages.map((msg) {
          final isUser = msg.isUser;
          return Align(
            alignment:
                isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14.0, vertical: 10.0),
              constraints: BoxConstraints(
                maxWidth:
                    MediaQuery.of(context).size.width * 0.82,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? (isDark ? TuskColors.pureWhite : TuskColors.pureBlack)
                    : cardBg,
                borderRadius: BorderRadius.circular(12),
                border:
                    isUser ? null : Border.all(color: cardBorder),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: isUser
                      ? (isDark
                          ? TuskColors.pureBlack
                          : TuskColors.pureWhite)
                      : textPrimary,
                ),
              ),
            ),
          );
        }),

        // System messages shown as info banners
        ...systemMessages.map((text) => Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cardBorder),
              ),
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? TuskColors.darkTextSecondary
                        : TuskColors.lightTextSecondary,
                    height: 1.4),
              ),
            )),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final List<String> examples;
  final TextEditingController composerController;
  final Color textPrimary;
  final Color textSecondary;
  final Color cardBg;
  final Color cardBorder;
  final bool isDark;

  const _EmptyState({
    required this.examples,
    required this.composerController,
    required this.textPrimary,
    required this.textSecondary,
    required this.cardBg,
    required this.cardBorder,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'What outcome do you want to achieve?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'State your goal in ordinary language. '
            'Tusk.ai will clarify details and build a step-by-step plan.',
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'EXAMPLE MISSIONS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark
                  ? TuskColors.darkTextMuted
                  : TuskColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 12),
          ...examples.map((prompt) => Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: InkWell(
                  key: Key('example_mission_${prompt.hashCode}'),
                  onTap: () {
                    composerController.text = prompt;
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.arrowRight,
                            size: 16, color: textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            prompt,
                            style: TextStyle(
                              fontSize: 14,
                              color: textPrimary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _ClarificationBanner extends StatelessWidget {
  final String question;
  final bool isDark;
  final Color cardBg;
  final Color cardBorder;
  final Color textSecondary;

  const _ClarificationBanner({
    required this.question,
    required this.isDark,
    required this.cardBg,
    required this.cardBorder,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.helpCircle, size: 18, color: textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CLARIFYING QUESTION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isDark
                        ? TuskColors.darkTextMuted
                        : TuskColors.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  question,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? TuskColors.darkTextPrimary
                          : TuskColors.lightTextPrimary,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningIndicator extends StatelessWidget {
  final bool isDark;
  final Color textSecondary;
  final bool usingRemote;
  const _PlanningIndicator(
      {required this.isDark, required this.textSecondary, this.usingRemote = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            usingRemote ? 'Generating AI plan...' : 'Generating local plan...',
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PlanReadyStrip extends StatelessWidget {
  final bool isDark;
  final MissionStatus status;
  final VoidCallback onReview;
  final Color textPrimary;
  final Color cardBg;
  final Color cardBorder;

  const _PlanReadyStrip({
    required this.isDark,
    required this.status,
    required this.onReview,
    required this.textPrimary,
    required this.cardBg,
    required this.cardBorder,
  });

  @override
  Widget build(BuildContext context) {
    final isApproved = status == MissionStatus.approved;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            isApproved ? LucideIcons.play : LucideIcons.clipboardList,
            size: 18,
            color: isDark
                ? TuskColors.darkTextSecondary
                : TuskColors.lightTextSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isApproved ? 'Plan approved — ready to execute' : 'Plan ready for review',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textPrimary),
            ),
          ),
          TextButton(
            key: Key(isApproved ? 'home_open_mission_button' : 'home_review_plan_button'),
            onPressed: onReview,
            child: Text(
              isApproved ? 'Open' : 'Review',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onMicTapped;
  final VoidCallback onSubmit;
  final bool isDark;
  final Color textSecondary;
  final Color cardBg;
  final Color dividerColor;
  final String hintText;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onMicTapped,
    required this.onSubmit,
    required this.isDark,
    required this.textSecondary,
    required this.cardBg,
    required this.dividerColor,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Microphone affordance — honest about unavailability
          IconButton(
            key: const Key('home_mic_button'),
            onPressed: onMicTapped,
            tooltip: 'Voice input (not yet available)',
            icon: Icon(LucideIcons.mic, size: 20, color: textSecondary),
            style: IconButton.styleFrom(
              backgroundColor: cardBg,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('home_mission_input'),
              controller: controller,
              focusNode: focusNode,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(hintText: hintText),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('home_send_button'),
            onPressed: onSubmit,
            tooltip: 'Submit goal',
            icon: Icon(
              LucideIcons.arrowUp,
              size: 20,
              color: isDark ? TuskColors.pureBlack : TuskColors.pureWhite,
            ),
            style: IconButton.styleFrom(
              backgroundColor:
                  isDark ? TuskColors.pureWhite : TuskColors.pureBlack,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionChip extends StatelessWidget {
  final MissionStatus status;
  const _MissionChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String label;
    switch (status) {
      case MissionStatus.needsClarification:
        label = 'Clarifying';
        break;
      case MissionStatus.readyForApproval:
        label = 'Review plan';
        break;
      case MissionStatus.approved:
        label = 'Approved';
        break;
      case MissionStatus.running:
        label = 'Running';
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? TuskColors.darkSurface : TuskColors.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? TuskColors.darkBorder : TuskColors.lightBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark
              ? TuskColors.darkTextSecondary
              : TuskColors.lightTextSecondary,
        ),
      ),
    );
  }
}
