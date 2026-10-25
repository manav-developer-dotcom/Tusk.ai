import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tusk_ai/core/network/api_config.dart';
import 'package:tusk_ai/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen Backend URL Configuration Tests', () {
    testWidgets('Settings renders backend tile with active URL', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            currentThemeMode: ThemeMode.system,
            onThemeChanged: (_) {},
            apiConfig: config,
          ),
        ),
      );

      expect(find.text('Mission Backend (FastAPI)'), findsOneWidget);
      expect(find.textContaining('Tap to configure'), findsOneWidget);
      expect(find.textContaining(config.baseUrl), findsOneWidget);
    });

    testWidgets('Tapping backend tile opens dialog and shows presets', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            currentThemeMode: ThemeMode.system,
            onThemeChanged: (_) {},
            apiConfig: config,
          ),
        ),
      );

      await tester.tap(find.text('Mission Backend (FastAPI)'));
      await tester.pumpAndSettle();

      expect(find.text('Backend Server URL'), findsOneWidget);
      expect(find.text('QUICK PRESETS'), findsOneWidget);
      expect(find.byKey(const Key('backend_url_input')), findsOneWidget);
      expect(find.byKey(const Key('reset_backend_url_button')), findsOneWidget);
      expect(find.byKey(const Key('save_backend_url_button')), findsOneWidget);

      // Verify preset chips are present
      expect(find.text('Wi-Fi PC (192.168.0.110)'), findsOneWidget);
      expect(find.text('Emulator (10.0.2.2)'), findsOneWidget);
      expect(find.text('Localhost (127.0.0.1)'), findsOneWidget);
    });

    testWidgets('Selecting Wi-Fi preset and tapping Save updates active URL', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      String? reportedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            currentThemeMode: ThemeMode.system,
            onThemeChanged: (_) {},
            apiConfig: config,
            onBaseUrlChanged: (url) => reportedUrl = url,
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Mission Backend (FastAPI)'));
      await tester.pumpAndSettle();

      // Tap Wi-Fi preset chip
      await tester.tap(find.text('Wi-Fi PC (192.168.0.110)'));
      await tester.pump();

      // Tap Save button
      await tester.tap(find.byKey(const Key('save_backend_url_button')));
      await tester.pumpAndSettle();

      // Dialog closed
      expect(find.text('Backend Server URL'), findsNothing);

      // Verify config was updated
      expect(config.baseUrl, equals('http://192.168.0.110:8000'));
      expect(config.isCustomBaseUrl, isTrue);
      expect(reportedUrl, equals('http://192.168.0.110:8000'));

      // Verify custom badge and new URL in UI
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('http://192.168.0.110:8000 • Tap to configure'), findsOneWidget);
    });

    testWidgets('Tapping Reset Default clears custom URL and restores platform default', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);
      await config.setBaseUrl('http://192.168.0.110:8000');

      String? reportedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            currentThemeMode: ThemeMode.system,
            onThemeChanged: (_) {},
            apiConfig: config,
            onBaseUrlChanged: (url) => reportedUrl = url,
          ),
        ),
      );

      // Verify Custom badge is initially shown
      expect(find.text('Custom'), findsOneWidget);

      // Open dialog
      await tester.tap(find.text('Mission Backend (FastAPI)'));
      await tester.pumpAndSettle();

      // Tap Reset Default button
      await tester.tap(find.byKey(const Key('reset_backend_url_button')));
      await tester.pumpAndSettle();

      // Verify config is reset
      expect(config.isCustomBaseUrl, isFalse);
      expect(config.baseUrl, equals(ApiConfig.resolveDefaultBaseUrl()));
      expect(reportedUrl, equals(ApiConfig.resolveDefaultBaseUrl()));

      // Custom badge should no longer be visible
      expect(find.text('Custom'), findsNothing);
    });
  });
}
