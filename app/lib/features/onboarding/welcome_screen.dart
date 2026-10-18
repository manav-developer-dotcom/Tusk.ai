import 'package:flutter/material.dart';
import '../../core/theme/tusk_theme.dart';
import '../../core/widgets/tusk_wordmark_shine.dart';

/// Clean welcome screen for Tusk.ai.
/// The cinematic shine already played on cold launch; here the wordmark
/// is displayed statically so users immediately recognize the brand.
class WelcomeScreen extends StatelessWidget {
  final VoidCallback onGetStarted;

  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
  });

  @override
  Widget build(BuildContext context) {
    const textPrimary = TuskColors.darkTextPrimary;
    const textSecondary = TuskColors.darkTextSecondary;
    const btnBackground = TuskColors.pureWhite;
    const btnForeground = TuskColors.pureBlack;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              // Static wordmark — shine already played on cold launch
              const TuskWordmarkShine(fontSize: 44, animate: false),
              const SizedBox(height: 20),
              const Text(
                'Turn intent into completed, verifiable work.',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Describe an outcome. Review the plan. Let Tusk coordinate the tools.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: textSecondary,
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  key: const Key('welcome_get_started_button'),
                  onPressed: onGetStarted,
                  style: FilledButton.styleFrom(
                    backgroundColor: btnBackground,
                    foregroundColor: btnForeground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Get started',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Local development session \u2022 No account required',
                  style: TextStyle(
                    fontSize: 12,
                    color: TuskColors.darkTextMuted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
