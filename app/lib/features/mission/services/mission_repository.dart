import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mission.dart';
import 'mission_api_service.dart';

/// Unified storage and coordination repository for Tusk.ai missions.
///
/// Supports both:
/// 1. Remote backend synchronization when [apiService] is connected.
/// 2. Offline and local persistence via SharedPreferences cache.
///
/// Conversation-deletion policy (PRODUCT_DECISIONS.md):
/// When a conversation is deleted, [detachConversation] sets
/// [Mission.conversationId] to null on all linked missions.
/// The missions are preserved so the user can still review what happened.
class MissionRepository {
  static const String _indexKey = 'tusk_missions_index_v1';
  static const String _missionKeyPrefix = 'tusk_mission_v1_';

  final SharedPreferences _prefs;
  final MissionApiService? apiService;

  MissionRepository(this._prefs, {this.apiService});

  static Future<MissionRepository> create({MissionApiService? apiService}) async {
    final prefs = await SharedPreferences.getInstance();
    return MissionRepository(prefs, apiService: apiService);
  }

  bool get hasRemoteBackend => apiService != null;

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

  /// Load all cached missions ordered by [Mission.updatedAt] descending.
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

  /// Load a single mission by ID from local cache.
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

  /// Upsert a mission into local cache.
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

  /// Create a mission via the backend, cache it locally, and associate with conversation.
  Future<Mission> createRemoteMission({
    required String goal,
    String? conversationId,
    String? clientRequestId,
  }) async {
    if (apiService != null) {
      final remoteMission = await apiService!.createMission(
        goal: goal,
        conversationId: conversationId,
        clientRequestId: clientRequestId,
      );
      await saveMission(remoteMission);
      return remoteMission;
    }

    // Local fallback if no remote service is configured
    final now = DateTime.now();
    final missionId = 'mission_${now.millisecondsSinceEpoch}';
    final shortTitle = goal.length > 60 ? '${goal.substring(0, 60)}...' : goal;
    final mission = Mission(
      id: missionId,
      objective: goal,
      title: shortTitle,
      conversationId: conversationId,
      createdAt: now,
      updatedAt: now,
    );
    await saveMission(mission);
    return mission;
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
  Future<bool> updateStatus(
    String missionId,
    MissionStatus newStatus, {
    String? failureReason,
    String? resultSummary,
  }) async {
    // If backend is active and transition is cancel or retry, sync remotely
    if (apiService != null) {
      try {
        if (newStatus == MissionStatus.cancelled) {
          final updated = await apiService!.cancelMission(
            missionId,
            failureReason ?? 'Cancelled by user.',
          );
          await saveMission(updated);
          return true;
        } else if (newStatus == MissionStatus.readyForApproval) {
          final updated = await apiService!.retryMission(missionId);
          await saveMission(updated);
          return true;
        }
      } catch (_) {
        // Fall back to local state transition if offline
      }
    }

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
    if (apiService != null) {
      try {
        final updated = await apiService!.approveMission(missionId);
        // Preserve local conversationId linkage
        final existing = loadMission(missionId);
        if (existing?.conversationId != null) {
          updated.conversationId = existing!.conversationId;
        }
        await saveMission(updated);
        return true;
      } catch (_) {
        // Fall back to local approval if offline
      }
    }

    final m = loadMission(missionId);
    if (m == null) return false;
    final ok = m.transitionTo(MissionStatus.approved);
    if (!ok) return false;
    m.approvedByUser = true;
    await saveMission(m);
    return true;
  }

  /// Fetch remote missions and sync with local cache.
  Future<List<Mission>> syncRemoteMissions() async {
    if (apiService == null) return loadMissions();
    try {
      final remoteMissions = await apiService!.listMissions();
      for (final r in remoteMissions) {
        final existing = loadMission(r.id);
        if (existing?.conversationId != null) {
          r.conversationId = existing!.conversationId;
        }
        await saveMission(r);
      }
      return loadMissions();
    } catch (_) {
      return loadMissions();
    }
  }

  /// Execute an approved mission on the backend, update steps, and cache deliverables.
  Future<Mission?> executeMission(String missionId) async {
    if (apiService != null) {
      final updated = await apiService!.executeMission(missionId);
      final existing = loadMission(missionId);
      if (existing?.conversationId != null) {
        updated.conversationId = existing!.conversationId;
      }
      // Also fetch and attach artifacts
      try {
        final artifacts = await apiService!.listArtifacts(missionId);
        updated.artifacts = artifacts;
      } catch (_) {}

      await saveMission(updated);
      return updated;
    }
    return null;
  }

  /// Retrieve persistent artifacts associated with a mission.
  Future<List<MissionArtifact>> fetchArtifacts(String missionId) async {
    if (apiService != null) {
      try {
        final artifacts = await apiService!.listArtifacts(missionId);
        final existing = loadMission(missionId);
        if (existing != null) {
          existing.artifacts = artifacts;
          await saveMission(existing);
        }
        return artifacts;
      } catch (_) {
        return loadMission(missionId)?.artifacts ?? [];
      }
    }
    return loadMission(missionId)?.artifacts ?? [];
  }

  /// Download the text content of a deliverable artifact.
  Future<String> getArtifactContent(String artifactId) async {
    if (apiService != null) {
      return apiService!.getArtifactContent(artifactId);
    }
    return '';
  }
}
