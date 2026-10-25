import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Predefined backend target preset for simple selection in Settings.
class BackendPreset {
  final String label;
  final String url;
  final String description;

  const BackendPreset({
    required this.label,
    required this.url,
    required this.description,
  });
}

/// Configuration for backend API connectivity, platform-specific URL resolution,
/// custom base URL persistence, and session identity.
class ApiConfig extends ChangeNotifier {
  static const String _sessionKey = 'tusk_anonymous_session_v1';
  static const String _baseUrlKey = 'tusk_custom_base_url_v1';

  /// Standard development endpoints
  static const String emulatorBaseUrl = 'http://10.0.2.2:8000';
  static const String localHostBaseUrl = 'http://127.0.0.1:8000';
  static const String defaultLanBaseUrl = 'http://192.168.0.110:8000';

  /// Quick-select presets for local testing across environments
  static const List<BackendPreset> presets = [
    BackendPreset(
      label: 'Wi-Fi PC (192.168.0.110)',
      url: defaultLanBaseUrl,
      description: 'Physical Android phone on LAN',
    ),
    BackendPreset(
      label: 'Emulator (10.0.2.2)',
      url: emulatorBaseUrl,
      description: 'Android Studio emulator loopback',
    ),
    BackendPreset(
      label: 'Localhost (127.0.0.1)',
      url: localHostBaseUrl,
      description: 'Web & desktop development',
    ),
  ];

  final SharedPreferences _prefs;

  ApiConfig(this._prefs);

  /// Normalize a raw URL string:
  /// - Strips whitespace
  /// - Strips trailing slashes
  /// - Prepend http:// if no scheme is provided
  static String normalizeBaseUrl(String url) {
    var clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return clean;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    return clean;
  }

  /// Validate if a given URL is a well-formed HTTP/HTTPS endpoint.
  static bool isValidUrl(String url) {
    if (url.trim().isEmpty) return false;
    final normalized = normalizeBaseUrl(url);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  /// Determine the default backend base URL based on runtime platform or compile-time env.
  /// Android emulators route loopback through 10.0.2.2 to reach the host machine.
  static String resolveDefaultBaseUrl() {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return normalizeBaseUrl(fromEnv);

    if (kIsWeb) {
      return localHostBaseUrl;
    }

    try {
      if (Platform.isAndroid) {
        return emulatorBaseUrl;
      }
    } catch (_) {
      // Fallback for non-standard test environments
    }

    return localHostBaseUrl;
  }

  /// Get the active API base URL (custom override or platform default).
  String get baseUrl {
    final custom = _prefs.getString(_baseUrlKey);
    if (custom != null && custom.trim().isNotEmpty) {
      return normalizeBaseUrl(custom);
    }
    return resolveDefaultBaseUrl();
  }

  /// Check if a custom base URL has been configured.
  bool get isCustomBaseUrl {
    final custom = _prefs.getString(_baseUrlKey);
    return custom != null && custom.trim().isNotEmpty;
  }

  /// Override the API base URL at runtime (e.g. from Settings or dev testing).
  Future<void> setBaseUrl(String url) async {
    final normalized = normalizeBaseUrl(url);
    await _prefs.setString(_baseUrlKey, normalized);
    notifyListeners();
  }

  /// Reset the API base URL back to default.
  Future<void> resetBaseUrl() async {
    await _prefs.remove(_baseUrlKey);
    notifyListeners();
  }

  /// Retrieve or generate a stable anonymous device session identifier.
  String get sessionId {
    final existing = _prefs.getString(_sessionKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final newSession = 'session_${DateTime.now().millisecondsSinceEpoch}_${_randomHex(6)}';
    _prefs.setString(_sessionKey, newSession);
    return newSession;
  }

  static String _randomHex(int length) {
    const chars = '0123456789abcdef';
    final now = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(chars[(now + i * 17) % chars.length]);
    }
    return buffer.toString();
  }
}
