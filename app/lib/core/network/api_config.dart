import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for backend API connectivity and session persistence.
class ApiConfig {
  static const String _sessionKey = 'tusk_anonymous_session_v1';
  static const String _baseUrlKey = 'tusk_custom_base_url_v1';

  final SharedPreferences _prefs;

  ApiConfig(this._prefs);

  /// Determine the default backend base URL based on runtime platform.
  /// Android emulators route loopback through 10.0.2.2 to reach host machine.
  static String resolveDefaultBaseUrl() {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;

    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }

    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8000';
      }
    } catch (_) {
      // Fallback for non-standard test environments
    }

    return 'http://127.0.0.1:8000';
  }

  /// Get the active API base URL (custom override or platform default).
  String get baseUrl {
    final custom = _prefs.getString(_baseUrlKey);
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
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
    await _prefs.setString(_baseUrlKey, url.trim());
  }

  /// Reset the API base URL back to default.
  Future<void> resetBaseUrl() async {
    await _prefs.remove(_baseUrlKey);
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
