import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mission.dart';

/// Persistent local storage for missions, backed by SharedPreferences.
///
/// Each mission is stored individually under a key derived from its ID,
/// and a separate index key maintains the ordered list of IDs.
///
/// Conversation-deletion policy (PRODUCT_DECISIONS.md):
/// When a conversation is deleted, [detachConversation] sets
/// [Mission.conversationId] to null on all linked missions.
/// The missions are preserved so the user can still review what happened.
class MissionRepository {
  static const String _indexKey = 'tusk_missions_index_v1';
  static const String _missionKeyPrefix = 'tusk_mission_v1_';

  final SharedPreferences _prefs;

  MissionRepository(this._prefs);

  static Future<MissionRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return MissionRepository(prefs);
  }

  // ── Index helpers ───────────────────────────────────────

  List<String> _loadIndex() {
    final raw = _prefs.getString(_indexKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveIndex(List<String> ids) async {
    await _prefs.setString(_indexKey, jsonEncode(ids));
  }

  // ── CRUD ────────────────────────────────────────────────

  /// Load all missions ordered by [Mission.updatedAt] descending.
  List<Mission> loadMissions() {
    final ids = _loadIndex();
    final missions = <Mission>[];
    for (final id in ids) {
      final raw = _prefs.getString('$_missionKeyPrefix$id');
      if (raw == null) continue;
      try {
        missions.add(Mission.fromJson(raw));
      } catch (_) {
        // Skip corrupted entries silently; do not crash the app.
      }
    }
    missions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return missions;
  }

  /// Load a single mission by ID. Returns null if not found.
  Mission? loadMission(String id) {
    final raw = _prefs.getString('$_missionKeyPrefix$id');
    if (raw == null) return null;
    try {
      return Mission.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// Alias for [loadMission].
  Mission? getMission(String id) => loadMission(id);

  /// Search missions by title and objective text.
  List<Mission> search(String query) {
    final all = loadMissions();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;

    return all.where((m) {
      final titleMatch = m.title.toLowerCase().contains(q);
      final objectiveMatch = m.objective.toLowerCase().contains(q);
      return titleMatch || objectiveMatch;
    }).toList();
  }

  /// Upsert a mission (create or update).
  Future<void> saveMission(Mission mission) async {
    await _prefs.setString(
      '$_missionKeyPrefix${mission.id}',
      mission.toJson(),
    );
    final ids = _loadIndex();
    if (!ids.contains(mission.id)) {
      ids.insert(0, mission.id);
      await _saveIndex(ids);
    }
  }

  /// Delete a mission and remove it from the index.
  Future<void> deleteMission(String id) async {
    await _prefs.remove('$_missionKeyPrefix$id');
    final ids = _loadIndex();
    ids.remove(id);
    await _saveIndex(ids);
  }

  /// Return missions associated with [conversationId].
  List<Mission> missionsForConversation(String conversationId) {
    return loadMissions()
        .where((m) => m.conversationId == conversationId)
        .toList();
  }

  /// Called when a conversation is deleted.
  /// Sets [conversationId] to null on all linked missions (preserves them).
  Future<void> detachConversation(String conversationId) async {
    final linked = missionsForConversation(conversationId);
    for (final m in linked) {
      m.conversationId = null;
      m.updatedAt = DateTime.now();
      await saveMission(m);
    }
  }

  /// Update mission status atomically; validates the transition.
  /// Returns false if the transition is invalid.
  Future<bool> updateStatus(
    String missionId,
    MissionStatus newStatus, {
    String? failureReason,
    String? resultSummary,
  }) async {
    final m = loadMission(missionId);
    if (m == null) return false;
    final ok = m.transitionTo(newStatus);
    if (!ok) return false;
    if (failureReason != null) m.failureReason = failureReason;
    if (resultSummary != null) m.resultSummary = resultSummary;
    await saveMission(m);
    return true;
  }

  /// Approve a mission (sets [Mission.approvedByUser] and transitions to approved).
  Future<bool> approveMission(String missionId) async {
    final m = loadMission(missionId);
    if (m == null) return false;
    final ok = m.transitionTo(MissionStatus.approved);
    if (!ok) return false;
    m.approvedByUser = true;
    await saveMission(m);
    return true;
  }
}
