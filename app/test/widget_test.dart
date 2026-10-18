import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tusk_ai/core/theme/tusk_theme.dart';
import 'package:tusk_ai/core/widgets/tusk_wordmark_shine.dart';
import 'package:tusk_ai/features/conversation/models/conversation.dart';
import 'package:tusk_ai/features/conversation/services/conversation_repository.dart';
import 'package:tusk_ai/features/conversation/widgets/conversation_sidebar.dart';
import 'package:tusk_ai/features/onboarding/welcome_screen.dart';
import 'package:tusk_ai/features/home/home_screen.dart';
import 'package:tusk_ai/features/mission/services/mission_repository.dart';

import 'package:tusk_ai/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tusk.ai Theme & Branding Tests', () {
    test('Dark theme tokens are strictly monochrome', () {
      final dark = TuskTheme.darkTheme();
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, TuskColors.darkBackground);
      expect(dark.colorScheme.primary, TuskColors.pureWhite);
    });

    test('Light theme tokens are strictly monochrome', () {
      final light = TuskTheme.lightTheme();
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, TuskColors.lightBackground);
      expect(light.colorScheme.primary, TuskColors.pureBlack);
    });

    testWidgets('Cold launch wordmark reads exactly TUSK and respects reduced motion', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: TuskWordmarkShine(animate: false),
            ),
          ),
        ),
      );

      // Verify the wordmark reads exactly 'TUSK' in capital
      expect(find.text('TUSK'), findsOneWidget);
      expect(find.text('Tusk.ai'), findsNothing);
    });

    testWidgets('Welcome screen renders with black background and TUSK wordmark', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WelcomeScreen(onGetStarted: () {}),
        ),
      );

      expect(find.text('TUSK'), findsOneWidget);
      expect(find.text('Turn intent into completed, verifiable work.'), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.black);
    });
  });

  group('Tusk.ai Persistence & Conversation Repository Tests', () {
    test('Conversations persist across repository reconstruction (app restart simulation)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final repo1 = ConversationRepository(prefs);
      final conv = Conversation(
        id: 'test_conv_1',
        title: 'Draft launch notes',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [
          Message(
            id: 'm1',
            text: 'Draft launch notes for product',
            isUser: true,
            timestamp: DateTime.now(),
          ),
        ],
      );
      await repo1.saveConversation(conv);

      // Simulate app restart by instantiating a new repository reading the same persisted prefs
      final repo2 = ConversationRepository(prefs);
      final loaded = repo2.loadConversations();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'test_conv_1');
      expect(loaded.first.title, 'Draft launch notes');
      expect(loaded.first.messages.length, 1);
      expect(loaded.first.messages.first.text, 'Draft launch notes for product');

      // Test rename
      await repo2.renameConversation('test_conv_1', 'Renamed launch notes');
      final repo3 = ConversationRepository(prefs);
      expect(repo3.loadConversations().first.title, 'Renamed launch notes');

      // Test search
      expect(repo3.search('launch').length, 1);
      expect(repo3.search('nonexistent').isEmpty, true);

      // Test delete
      await repo3.deleteConversation('test_conv_1');
      final repo4 = ConversationRepository(prefs);
      expect(repo4.loadConversations().isEmpty, true);
    });
  });

  group('Tusk.ai Sidebar & Navigation Tests', () {
    testWidgets('Sidebar displays empty state when no history exists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TuskTheme.darkTheme(),
          home: Scaffold(
            body: ConversationSidebar(
              conversations: const [],
              activeConversationId: null,
              onNewTask: () {},
              onSelectConversation: (_) {},
              onRenameConversation: (_, __) {},
              onDeleteConversation: (_) {},
              onOpenSettings: () {},
            ),
          ),
        ),
      );

      expect(find.text('TUSK'), findsOneWidget);
      expect(find.text('No previous conversations'), findsOneWidget);
      expect(find.byKey(const Key('sidebar_new_task_button')), findsOneWidget);
      expect(find.byKey(const Key('sidebar_search_input')), findsOneWidget);
    });

    testWidgets('Full flow: Splash -> Welcome -> Home -> Submit Goal -> Open Sidebar -> Verify Task & Search', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ConversationRepository(prefs);

      final missionRepo = MissionRepository(prefs);

      await tester.pumpWidget(TuskApp(convRepository: repo, missionRepository: missionRepo));
      await tester.pump();

      // Pump through full splash sequence: 1100ms animation + 220ms hold + 300ms fade-out + 280ms AnimatedOpacity
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pumpAndSettle();

      // Welcome Screen
      final getStartedBtn = find.byKey(const Key('welcome_get_started_button'));
      expect(getStartedBtn, findsOneWidget);
      await tester.tap(getStartedBtn);
      await tester.pumpAndSettle();

      // Home Screen - submit goal
      final inputFinder = find.byKey(const Key('home_mission_input'));
      await tester.enterText(inputFinder, 'Draft release notes');
      await tester.pump();

      final sendBtnFinder = find.byKey(const Key('home_send_button'));
      await tester.tap(sendBtnFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify message rendered in active conversation and title
      expect(find.text('Draft release notes'), findsAtLeastNWidgets(1));

      // Open Sidebar
      final sidebarBtn = find.byKey(const Key('home_sidebar_button'));
      await tester.tap(sidebarBtn);
      await tester.pumpAndSettle();

      // Verify conversation listed in sidebar
      expect(find.byType(ConversationSidebar), findsOneWidget);
      expect(find.text('Draft release notes'), findsAtLeastNWidgets(1));

      // Search in sidebar
      final searchInput = find.byKey(const Key('sidebar_search_input'));
      await tester.enterText(searchInput, 'release');
      await tester.pumpAndSettle();
      expect(find.text('Draft release notes'), findsAtLeastNWidgets(1));

      await tester.enterText(searchInput, 'xyznotfound');
      await tester.pumpAndSettle();
      expect(find.text('No matching tasks found'), findsOneWidget);

      // Clear search
      await tester.enterText(searchInput, '');
      await tester.pumpAndSettle();

      // Close sidebar via close button
      await tester.tap(find.byKey(const Key('sidebar_close_button')));
      await tester.pumpAndSettle();
    });

    testWidgets('Home composer shows honest feedback for voice mic affordance', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TuskTheme.darkTheme(),
          home: HomeScreen(
            activeConversation: null,
            onOpenSidebar: () {},
            onSubmitGoal: (_) {},
          ),
        ),
      );

      // Tap mic affordance and verify honest snackbar
      await tester.tap(find.byKey(const Key('home_mic_button')));
      await tester.pump();
      expect(find.text('Voice input requires platform speech APIs — available in a future phase.'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}
