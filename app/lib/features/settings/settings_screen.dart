import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_config.dart';
import '../../core/theme/tusk_theme.dart';

/// Settings screen for Tusk.ai.
/// Provides Light, Dark, and System theme controls.
/// Honestly discloses connected tool statuses without pretending mock services are live.
/// Includes interactive FastAPI backend URL configuration and live connectivity diagnostics.
class SettingsScreen extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ApiConfig? apiConfig;
  final ValueChanged<String>? onBaseUrlChanged;

  const SettingsScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
    this.apiConfig,
    this.onBaseUrlChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _activeBaseUrl;
  ApiConfig? _effectiveApiConfig;

  @override
  void initState() {
    super.initState();
    _effectiveApiConfig = widget.apiConfig;
    _effectiveApiConfig?.addListener(_onConfigChanged);
    if (_effectiveApiConfig == null) {
      SharedPreferences.getInstance().then((prefs) {
        if (mounted) {
          final cfg = ApiConfig(prefs);
          cfg.addListener(_onConfigChanged);
          setState(() {
            _effectiveApiConfig = cfg;
            _activeBaseUrl = cfg.baseUrl;
          });
        }
      });
    }
    _activeBaseUrl = _effectiveApiConfig?.baseUrl ?? ApiConfig.resolveDefaultBaseUrl();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiConfig != widget.apiConfig) {
      oldWidget.apiConfig?.removeListener(_onConfigChanged);
      _effectiveApiConfig = widget.apiConfig;
      _effectiveApiConfig?.addListener(_onConfigChanged);
      _activeBaseUrl = _effectiveApiConfig?.baseUrl ?? ApiConfig.resolveDefaultBaseUrl();
    }
  }

  @override
  void dispose() {
    _effectiveApiConfig?.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    if (mounted) {
      setState(() {
        _activeBaseUrl = _effectiveApiConfig?.baseUrl ?? ApiConfig.resolveDefaultBaseUrl();
      });
    }
  }

  void _refreshBaseUrl() {
    setState(() {
      _activeBaseUrl = _effectiveApiConfig?.baseUrl ?? widget.apiConfig?.baseUrl ?? ApiConfig.resolveDefaultBaseUrl();
    });
  }


  Future<void> _showBackendConfigDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary = isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final surfaceColor = isDark ? TuskColors.darkSurface : TuskColors.lightSurface;
    final borderColor = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;

    final controller = TextEditingController(text: _activeBaseUrl);
    String? testResult;
    bool isTesting = false;
    bool testSuccess = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> runHealthCheck(String targetUrl) async {
            setDialogState(() {
              isTesting = true;
              testResult = null;
            });

            final cleanUrl = ApiConfig.normalizeBaseUrl(targetUrl);
            try {
              final uri = Uri.parse('$cleanUrl/health');
              final response = await http.get(uri).timeout(const Duration(seconds: 4));
              if (response.statusCode == 200) {
                dynamic jsonBody;
                try {
                  jsonBody = jsonDecode(response.body);
                } catch (_) {}
                final status = jsonBody is Map ? (jsonBody['status'] ?? 'healthy') : 'healthy';
                final dbStatus = jsonBody is Map ? (jsonBody['database'] ?? 'connected') : 'connected';
                setDialogState(() {
                  isTesting = false;
                  testSuccess = true;
                  testResult = 'Reachable ($status, db: $dbStatus)';
                });
              } else {
                setDialogState(() {
                  isTesting = false;
                  testSuccess = false;
                  testResult = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
                });
              }
            } catch (e) {
              setDialogState(() {
                isTesting = false;
                testSuccess = false;
                testResult = 'Connection failed: ${e.toString().replaceAll('Exception: ', '')}';
              });
            }
          }

          return AlertDialog(
            backgroundColor: surfaceColor,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor),
            ),
            title: Row(
              children: [
                Icon(LucideIcons.server, size: 20, color: textPrimary),
                const SizedBox(width: 10),
                Text(
                  'Backend Server URL',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Specify the host and port of the Tusk.ai FastAPI service.',
                    style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('backend_url_input'),
                    controller: controller,
                    style: TextStyle(color: textPrimary, fontSize: 14, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      labelStyle: TextStyle(color: textSecondary, fontSize: 13),
                      hintText: ApiConfig.defaultLanBaseUrl,
                      hintStyle: TextStyle(color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted),
                      filled: true,
                      fillColor: isDark ? TuskColors.darkBackground : TuskColors.lightSurfaceElevated,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: textPrimary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'QUICK PRESETS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ApiConfig.presets.map((preset) {
                      return ActionChip(
                        key: Key('preset_${preset.label}'),
                        label: Text(preset.label, style: const TextStyle(fontSize: 11)),
                        backgroundColor: isDark ? TuskColors.darkBackground : TuskColors.lightSurfaceElevated,
                        side: BorderSide(color: borderColor),
                        onPressed: () {
                          controller.text = preset.url;
                          runHealthCheck(controller.text);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        key: const Key('test_connectivity_button'),
                        icon: isTesting
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: textPrimary),
                              )
                            : Icon(LucideIcons.activity, size: 14, color: textPrimary),
                        label: Text('Test Connectivity', style: TextStyle(fontSize: 12, color: textPrimary)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: isTesting ? null : () => runHealthCheck(controller.text),
                      ),
                    ],
                  ),
                  if (testResult != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? TuskColors.darkBackground : TuskColors.lightSurfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            testSuccess ? LucideIcons.checkCircle2 : LucideIcons.alertCircle,
                            size: 16,
                            color: textPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              testResult!,
                              style: TextStyle(
                                fontSize: 12,
                                color: textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const Key('reset_backend_url_button'),
                onPressed: () async {
                  final cfg = _effectiveApiConfig ?? widget.apiConfig;
                  if (cfg != null) {
                    await cfg.resetBaseUrl();
                  } else {
                    final prefs = await SharedPreferences.getInstance();
                    await ApiConfig(prefs).resetBaseUrl();
                  }
                  _refreshBaseUrl();
                  widget.onBaseUrlChanged?.call(_activeBaseUrl);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Backend reset to default: $_activeBaseUrl'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Text('Reset Default', style: TextStyle(color: textSecondary, fontSize: 13)),
              ),
              FilledButton(
                key: const Key('save_backend_url_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: textPrimary,
                  foregroundColor: isDark ? TuskColors.pureBlack : TuskColors.pureWhite,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final rawUrl = controller.text.trim();
                  if (rawUrl.isEmpty || !ApiConfig.isValidUrl(rawUrl)) {
                    setDialogState(() {
                      testSuccess = false;
                      testResult = 'Please enter a valid HTTP/HTTPS URL (e.g. ${ApiConfig.defaultLanBaseUrl})';
                    });
                    return;
                  }
                  final cfg = _effectiveApiConfig ?? widget.apiConfig;
                  if (cfg != null) {
                    await cfg.setBaseUrl(rawUrl);
                  } else {
                    final prefs = await SharedPreferences.getInstance();
                    final fallback = ApiConfig(prefs);
                    await fallback.setBaseUrl(rawUrl);
                    _effectiveApiConfig = fallback;
                  }
                  _refreshBaseUrl();
                  widget.onBaseUrlChanged?.call(_activeBaseUrl);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Backend URL updated: $_activeBaseUrl'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: const Text('Save', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary = isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final cardBg = isDark ? TuskColors.darkSurface : TuskColors.lightSurface;
    final cardBorder = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;

    final isCustom = (_effectiveApiConfig ?? widget.apiConfig)?.isCustomBaseUrl ?? false;


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
                    groupValue: widget.currentThemeMode,
                    activeColor: textPrimary,
                    onChanged: (mode) {
                      if (mode != null) widget.onThemeChanged(mode);
                    },
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_dark_radio'),
                    title: Text('Dark theme', style: TextStyle(color: textPrimary)),
                    subtitle: Text('Strict monochrome black & dark greys', style: TextStyle(color: textSecondary, fontSize: 13)),
                    value: ThemeMode.dark,
                    groupValue: widget.currentThemeMode,
                    activeColor: textPrimary,
                    onChanged: (mode) {
                      if (mode != null) widget.onThemeChanged(mode);
                    },
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  RadioListTile<ThemeMode>(
                    key: const Key('theme_light_radio'),
                    title: Text('Light theme', style: TextStyle(color: textPrimary)),
                    subtitle: Text('Crisp white & neutral borders', style: TextStyle(color: textSecondary, fontSize: 13)),
                    value: ThemeMode.light,
                    groupValue: widget.currentThemeMode,
                    activeColor: textPrimary,
                    onChanged: (mode) {
                      if (mode != null) widget.onThemeChanged(mode);
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
                    title: Row(
                      children: [
                        Text('Mission Backend (FastAPI)', style: TextStyle(color: textPrimary, fontSize: 15)),
                        const SizedBox(width: 8),
                        if (isCustom)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? TuskColors.darkSurfaceElevated : TuskColors.lightSurfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Text(
                              'Custom',
                              style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '$_activeBaseUrl • Tap to configure',
                      style: TextStyle(color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted, fontSize: 12),
                    ),
                    trailing: Icon(LucideIcons.chevronRight, size: 16, color: textSecondary),
                    onTap: () => _showBackendConfigDialog(context),
                  ),
                  Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
                  ListTile(
                    leading: Icon(LucideIcons.fileText, color: textSecondary, size: 20),
                    title: Text('Text Generation (Gemini)', style: TextStyle(color: textPrimary, fontSize: 15)),
                    subtitle: Text(
                      'gemini-3.8-flash • Planning & Execution',
                      style: TextStyle(color: isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted, fontSize: 12),
                    ),
                    trailing: Text(
                      'Phase 4 Live',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
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
                  Text('Tusk.ai v0.4.0 (Phase 4 Live)', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Real Gemini AI planning and execution engine with persistent SQLite missions and deliverables.',
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
