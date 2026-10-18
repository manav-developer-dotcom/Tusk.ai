import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tusk_ai/core/theme/tusk_theme.dart';
import 'package:tusk_ai/features/conversation/models/conversation.dart';
import 'package:tusk_ai/features/conversation/services/conversation_repository.dart';
import 'package:tusk_ai/features/home/home_screen.dart';
import 'package:tusk_ai/features/mission/models/mission.dart';
import 'package:tusk_ai/features/mission/services/local_planner.dart';
import 'package:tusk_ai/features/mission/services/mission_repository.dart';
import 'package:tusk_ai/features/mission/mission_detail_screen.dart';
import 'package:tusk_ai/features/projects/projects_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mission Model & State Machine Tests', () {
    test('State machine enforces valid transitions and rejects invalid moves', () {
      final now = DateTime.now();
      final mission = Mission(
        id: 'm_test_1',
        objective: 'Draft quarterly report',
        title: 'Draft quarterly report',
        createdAt: now,
        updatedAt: now,
      );

      expect(mission.status, MissionStatus.draft);
      expect(mission.canTransitionTo(MissionStatus.needsClarification), isTrue);
      expect(mission.canTransitionTo(MissionStatus.readyForApproval), isTrue);
      expect(mission.canTransitionTo(MissionStatus.running), isFalse); // cannot jump directly to running

      // Transition to needsClarification
      expect(mission.transitionTo(MissionStatus.needsClarification), isTrue);
      expect(mission.status, MissionStatus.needsClarification);

      // Clarified -> readyForApproval
      expect(mission.transitionTo(MissionStatus.readyForApproval), isTrue);
      expect(mission.status, MissionStatus.readyForApproval);

      // User approves -> approved
      expect(mission.transitionTo(MissionStatus.approved), isTrue);
      expect(mission.status, MissionStatus.approved);

      // Execution starts -> running
      expect(mission.transitionTo(MissionStatus.running), isTrue);
      expect(mission.status, MissionStatus.running);

      // Succeeded -> completed
      expect(mission.transitionTo(MissionStatus.completed), isTrue);
      expect(mission.status, MissionStatus.completed);
      expect(mission.isTerminal, isTrue);

      // Terminal state cannot transition to anything
      expect(mission.canTransitionTo(MissionStatus.running), isFalse);
      expect(mission.transitionTo(MissionStatus.draft), isFalse);
    });

    test('Retry path from failed back to readyForApproval works', () {
      final now = DateTime.now();
      final mission = Mission(
        id: 'm_retry',
        objective: 'Test retry',
        title: 'Test retry',
        status: MissionStatus.failed,
        createdAt: now,
        updatedAt: now,
      );

      expect(mission.canTransitionTo(MissionStatus.readyForApproval), isTrue);
      expect(mission.transitionTo(MissionStatus.readyForApproval), isTrue);
      expect(mission.status, MissionStatus.readyForApproval);
    });

    test('Mission & MissionStep serialization and deserialization round-trip', () {
      final now = DateTime.now();
      final original = Mission(
        id: 'm_ser_1',
        objective: 'Analyze competitor product features',
        title: 'Analyze competitor product features',
        conversationId: 'conv_123',
        status: MissionStatus.readyForApproval,
        steps: [
          MissionStep(
            id: 's1',
            title: 'Identify competitors',
            description: 'List top 3 competitors',
            expectedOutput: 'Competitor list',
            status: StepStatus.completed,
          ),
          MissionStep(
            id: 's2',
            title: 'Matrix comparison',
            description: 'Map features across competitors',
            dependsOn: ['s1'],
            expectedOutput: 'Feature matrix',
            status: StepStatus.pending,
          ),
        ],
        clarifications: [
          ClarificationQuestion(
            id: 'q1',
            question: 'Which market segment?',
            answer: 'Enterprise SaaS',
          ),
        ],
        createdAt: now,
        updatedAt: now,
        approvedByUser: false,
      );

      final jsonStr = original.toJson();
      final reconstructed = Mission.fromJson(jsonStr);

      expect(reconstructed.id, original.id);
      expect(reconstructed.objective, original.objective);
      expect(reconstructed.conversationId, original.conversationId);
      expect(reconstructed.status, MissionStatus.readyForApproval);
      expect(reconstructed.steps.length, 2);
      expect(reconstructed.steps.first.title, 'Identify competitors');
      expect(reconstructed.steps.first.status, StepStatus.completed);
      expect(reconstructed.steps.last.dependsOn, ['s1']);
      expect(reconstructed.clarifications.length, 1);
      expect(reconstructed.clarifications.first.answer, 'Enterprise SaaS');
      expect(reconstructed.completedStepCount, 1);
    });
  });

  group('Mission Repository Persistence Tests', () {
    test('Missions persist across repository reconstruction (restart simulation)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final repo1 = MissionRepository(prefs);
      final now = DateTime.now();
      final mission = Mission(
        id: 'm_persist_1',
        objective: 'Write release notes',
        title: 'Write release notes',
        conversationId: 'c_abc',
        status: MissionStatus.readyForApproval,
        createdAt: now,
        updatedAt: now,
      );
      await repo1.saveMission(mission);

      // Re-instantiate repository reading from same SharedPreferences
      final repo2 = MissionRepository(prefs);
      final loaded = repo2.loadMissions();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'm_persist_1');
      expect(loaded.first.title, 'Write release notes');
      expect(loaded.first.conversationId, 'c_abc');

      // Test approve
      await repo2.approveMission('m_persist_1');
      final repo3 = MissionRepository(prefs);
      final approved = repo3.getMission('m_persist_1');
      expect(approved?.status, MissionStatus.approved);
      expect(approved?.approvedByUser, isTrue);

      // Test search
      expect(repo3.search('release').length, 1);
      expect(repo3.search('nonexistent').isEmpty, isTrue);

      // Test conversation detach
      await repo3.detachConversation('c_abc');
      final repo4 = MissionRepository(prefs);
      expect(repo4.getMission('m_persist_1')?.conversationId, isNull);

      // Test delete
      await repo4.deleteMission('m_persist_1');
      final repo5 = MissionRepository(prefs);
      expect(repo5.loadMissions().isEmpty, isTrue);
    });
  });

  group('Local Planner Adapter Tests', () {
    const planner = LocalPlannerAdapter();

    test('Identifies vague goals that require clarification', () {
      expect(planner.needsClarification('stuff'), isTrue);
      expect(planner.needsClarification('do it'), isTrue);
      expect(planner.needsClarification('something'), isTrue);
      expect(planner.needsClarification('short'), isTrue); // < 10 chars
    });

    test('Identifies specific goals that can proceed directly to planning', () {
      expect(planner.needsClarification('Draft a release announcement for our beta version'), isFalse);
      expect(planner.needsClarification('Research competitors in the enterprise CRM space'), isFalse);
    });

    test('Generates structured writing plan with sequential dependencies', () {
      final steps = planner.generatePlan('m_write', 'Write a clear technical specification', []);
      expect(steps.length, greaterThanOrEqualTo(3));
      expect(steps.first.dependsOn.isEmpty, isTrue);
      // Later steps depend on earlier ones
      expect(steps[1].dependsOn, contains(steps[0].id));
      for (final step in steps) {
        expect(step.title.isNotEmpty, isTrue);
        expect(step.description.isNotEmpty, isTrue);
        expect(step.expectedOutput.isNotEmpty, isTrue);
        expect(step.status, StepStatus.pending);
      }
    });

    test('Generates structured research plan', () {
      final steps = planner.generatePlan('m_res', 'Research battery technologies for EVs', []);
      expect(steps.length, 3);
      expect(steps.first.title, 'Define research questions');
    });
  });

  group('Mission UX Flow & Widget Tests', () {
    testWidgets('Home: Submitting vague goal triggers inline clarification question', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final missionRepo = MissionRepository(prefs);
      final convRepo = ConversationRepository(prefs);

      // Create an active conversation
      final conv = Conversation(
        id: 'conv_clarify',
        title: 'New conversation',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await convRepo.saveConversation(conv);

      await tester.pumpWidget(
        MaterialApp(
          theme: TuskTheme.darkTheme(),
          home: HomeScreen(
            activeConversation: conv,
            onOpenSidebar: () {},
            onSubmitGoal: (_) {},
            missionRepository: missionRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Submit a vague goal: "something"
      final input = find.byKey(const Key('home_mission_input'));
      await tester.enterText(input, 'something');
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_send_button')));
      await tester.pumpAndSettle();

      // Clarification card should appear with question
      expect(find.text('CLARIFYING QUESTION'), findsOneWidget);
      expect(find.text('What is the specific desired outcome for this goal?'), findsOneWidget);

      // Answer the question in the composer
      await tester.enterText(input, 'A complete launch plan for the mobile app');
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_send_button')));
      await tester.pumpAndSettle();

      // Should advance to next question or plan
      final mission = missionRepo.missionsForConversation('conv_clarify').first;
      expect(mission.clarifications.first.answer, 'A complete launch plan for the mobile app');
    });

    testWidgets('Home: Submitting specific goal generates plan and shows review strip', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final missionRepo = MissionRepository(prefs);
      final convRepo = ConversationRepository(prefs);

      final conv = Conversation(
        id: 'conv_plan_ready',
        title: 'New conversation',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await convRepo.saveConversation(conv);

      await tester.pumpWidget(
        MaterialApp(
          theme: TuskTheme.darkTheme(),
          home: HomeScreen(
            activeConversation: conv,
            onOpenSidebar: () {},
            onSubmitGoal: (_) {},
            missionRepository: missionRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Submit specific goal
      final input = find.byKey(const Key('home_mission_input'));
      await tester.enterText(input, 'Draft a release announcement for our beta version');
      await tester.pump();
      await tester.tap(find.byKey(const Key('home_send_button')));
      await tester.pumpAndSettle();

      // Should show plan-ready strip
      expect(find.text('Plan ready for review'), findsOneWidget);
      expect(find.byKey(const Key('home_review_plan_button')), findsOneWidget);
    });

    testWidgets('MissionDetailScreen: displays objective, dev adapter banner, plan steps, and handles approve', (tester) async {
      final now = DateTime.now();
      const planner = LocalPlannerAdapter();
      final steps = planner.generatePlan('m_detail', 'Write a release blog post', []);

      final mission = Mission(
        id: 'm_detail',
        objective: 'Write a release blog post',
        title: 'Write a release blog post',
        status: MissionStatus.readyForApproval,
        steps: steps,
        createdAt: now,
        updatedAt: now,
      );

      bool approved = false;
      bool cancelled = false;

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: TuskTheme.darkTheme(),
          home: MissionDetailScreen(
            mission: mission,
            onApprove: () => approved = true,
            onCancel: () => cancelled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check objective
      expect(find.text('OBJECTIVE'), findsOneWidget);
      expect(find.text('Write a release blog post'), findsAtLeastNWidgets(1));

      // Check dev adapter banner is present and visibly labeled
      expect(find.text('DEVELOPMENT ADAPTER'), findsOneWidget);
      expect(find.textContaining('rule-based planner'), findsOneWidget);

      // Check plan steps
      expect(find.text('PLAN'), findsOneWidget);
      expect(find.textContaining('Define scope and audience'), findsOneWidget);
      expect(find.textContaining('Create an outline'), findsOneWidget);

      // Check action buttons
      final approveBtn = find.byKey(const Key('mission_approve_button'));
      await tester.ensureVisible(approveBtn);
      await tester.pumpAndSettle();
      expect(approveBtn, findsOneWidget);

      final cancelBtn = find.byKey(const Key('mission_cancel_button'));
      expect(cancelBtn, findsOneWidget);

      // Tap approve
      await tester.tap(approveBtn);
      await tester.pumpAndSettle();
      expect(approved, isTrue);

      // Tap cancel
      await tester.ensureVisible(cancelBtn);
      await tester.pumpAndSettle();
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
    });

    testWidgets('ProjectsScreen: displays empty state and renders mission tiles when present', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final missionRepo = MissionRepository(prefs);

      // 1. Empty state
      await tester.pumpWidget(
        MaterialApp(
          theme: TuskTheme.darkTheme(),
          home: ProjectsScreen(missionRepository: missionRepo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No missions yet'), findsOneWidget);

      // 2. Add a mission and re-pump
      final now = DateTime.now();
      final mission = Mission(
        id: 'proj_m1',
        objective: 'Draft Q3 roadmap',
        title: 'Draft Q3 roadmap',
        status: MissionStatus.readyForApproval,
        steps: const LocalPlannerAdapter().generatePlan('proj_m1', 'Draft Q3 roadmap', []),
        createdAt: now,
        updatedAt: now,
      );
      await missionRepo.saveMission(mission);

      await tester.pumpWidget(
        MaterialApp(
          theme: TuskTheme.darkTheme(),
          home: ProjectsScreen(missionRepository: missionRepo),
        ),
      );
      await tester.pumpAndSettle();

      // Verify mission appears
      expect(find.text('Draft Q3 roadmap'), findsOneWidget);
      expect(find.text('Review plan'), findsOneWidget);
      expect(find.text('0 / 4 steps'), findsOneWidget);
    });
  });
}
