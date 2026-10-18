import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/network/api_config.dart';
import '../../core/theme/tusk_theme.dart';

/// Settings screen for Tusk.ai.
/// Provides Light, Dark, and System theme controls.
/// Honestly discloses connected tool statuses without pretending mock services are live.
class SettingsScreen extends StatelessWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ApiConfig? apiConfig;

  const SettingsScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
    this.apiConfig,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary = isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final cardBg = isDark ? TuskColors.darkSurface : TuskColors.lightSurface;
    final cardBorder = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          children: [
            // Appearance Section
            Text(
              'APPEARANCE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_system_radio'),
                    title: Text('System default', style: TextStyle(color: textPrimary)),
                    subtitle: Text('Match device appearance', style: TextStyle(color: textSecondary, fontSize: 13)),
                    value: ThemeMode.system,
                    groupValue: currentThemeMode,
                    activeColor: textPrimary,
                    onChanged: (mode) {
                      if (mode != null) onThemeChanged(mode);
                    },
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_dark_radio'),
                    title: Text('Dark theme', style: TextStyle(color: textPrimary)),
                    subtitle: Text('Strict monochrome black & dark greys', style: TextStyle(color: textSecondary, fontSize: 13)),
                    value: ThemeMode.dark,
                    groupValue: currentThemeMode,
                    activeColor: textPrimary,
                    onChanged: (mode) {
                      if (mode != null) onThemeChanged(mode);
                    },
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_light_radio'),
                    title: Text('Light theme', style: TextStyle(color: textPrimary)),
                    subtitle: Text('Crisp white & neutral borders', style: TextStyle(color: textSecondary, fontSize: 13)),
                    value: ThemeMode.light,
                    groupValue: currentThemeMode,
                    activeColor: textPrimary,
                    onChanged: (mode) {
                      if (mode != null) onThemeChanged(mode);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Connected Tools Section
            Text(
              'CONNECTED TOOLS & CAPABILITIES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(LucideIcons.server, color: textSecondary, size: 20),
                    title: Text('Mission Backend (FastAPI)', style: TextStyle(color: textPrimary, fontSize: 15)),
                    subtitle: Text(
                      apiConfig?.baseUrl ?? ApiConfig.resolveDefaultBaseUrl(),
                      style: TextStyle(color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted, fontSize: 12),
                    ),
                    trailing: Text(
                      'Phase 3 Live',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  ListTile(
                    leading: Icon(LucideIcons.fileText, color: textSecondary, size: 20),
                    title: Text('Text Generation (LLM)', style: TextStyle(color: textPrimary, fontSize: 15)),
                    trailing: Text(
                      'Phase 4',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted,
                      ),
                    ),
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  ListTile(
                    leading: Icon(LucideIcons.image, color: textSecondary, size: 20),
                    title: Text('Image Generation', style: TextStyle(color: textPrimary, fontSize: 15)),
                    trailing: Text(
                      'Phase 4',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted,
                      ),
                    ),
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  ListTile(
                    leading: Icon(LucideIcons.mic, color: textSecondary, size: 20),
                    title: Text('Voice & Transcription', style: TextStyle(color: textPrimary, fontSize: 15)),
                    trailing: Text(
                      'Phase 2',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // About Section
            Text(
              'ABOUT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tusk.ai v0.3.0 (Phase 3)', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Connected to persistent FastAPI SQLite backend. Independent action assistant architecture.',
                    style: TextStyle(color: textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

