import '../../../core/network/api_client.dart';
import '../models/mission.dart';

/// Service for remote Mission operations via the Tusk.ai backend.
class MissionApiService {
  final ApiClient client;

  MissionApiService(this.client);

  /// Check server connectivity and health.
  Future<bool> checkHealth() async {
    try {
      final res = await client.get('/health');
      if (res is Map<String, dynamic> && res['status'] == 'healthy') {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Submit a goal to the backend and receive an initial plan or clarification state.
  Future<Mission> createMission({
    required String goal,
    Map<String, dynamic>? context,
    String? clientRequestId,
    String? conversationId,
  }) async {
    final payload = {
      'goal': goal,
      if (context != null) 'context': context,
      if (clientRequestId != null) 'client_request_id': clientRequestId,
    };

    final res = await client.post(
      '/v1/missions',
      body: payload,
      requestTimeout: const Duration(seconds: 60),
    );
    final mission = _parseMission(res as Map<String, dynamic>);
    if (conversationId != null) {
      mission.conversationId = conversationId;
    }
    return mission;
  }

  /// List all missions belonging to the active device session.
  Future<List<Mission>> listMissions({int limit = 50, int offset = 0}) async {
    final res = await client.get('/v1/missions', queryParams: {
      'limit': limit,
      'offset': offset,
    });
    if (res is Map<String, dynamic> && res.containsKey('missions')) {
      final list = res['missions'] as List<dynamic>;
      return list.map((m) => _parseMission(m as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// Retrieve full mission details and plan by ID.
  Future<Mission> getMission(String missionId) async {
    final res = await client.get('/v1/missions/$missionId');
    return _parseMission(res as Map<String, dynamic>);
  }

  /// Approve a planned mission.
  Future<Mission> approveMission(String missionId) async {
    final res = await client.post('/v1/missions/$missionId/approve');
    return _parseMission(res as Map<String, dynamic>);
  }

  /// Execute an approved mission with real backend tool execution.
  Future<Mission> executeMission(String missionId) async {
    final res = await client.post(
      '/v1/missions/$missionId/execute',
      requestTimeout: const Duration(seconds: 180),
    );
    return _parseMission(res as Map<String, dynamic>);
  }

  /// List persistent deliverable artifacts generated for a mission.
  Future<List<MissionArtifact>> listArtifacts(String missionId) async {
    final res = await client.get('/v1/missions/$missionId/artifacts');
    if (res is Map<String, dynamic> && res.containsKey('artifacts')) {
      final list = res['artifacts'] as List<dynamic>;
      return list.map((a) => MissionArtifact.fromMap(a as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// Download the text content of a generated artifact deliverable.
  Future<String> getArtifactContent(String artifactId) async {
    final res = await client.get('/v1/artifacts/$artifactId/content');
    return res?.toString() ?? '';
  }

  /// Cancel an in-progress or planned mission.
  Future<Mission> cancelMission(String missionId, [String reason = 'Cancelled by user.']) async {
    final res = await client.post(
      '/v1/missions/$missionId/cancel',
      body: {'reason': reason},
    );
    return _parseMission(res as Map<String, dynamic>);
  }

  /// Retry an eligible failed mission.
  Future<Mission> retryMission(String missionId) async {
    final res = await client.post('/v1/missions/$missionId/retry');
    return _parseMission(res as Map<String, dynamic>);
  }

  /// Parse the backend JSON response into the Flutter domain Mission model.
  static Mission _parseMission(Map<String, dynamic> map) {
    final plan = map['plan'] as Map<String, dynamic>?;
    final rawSteps = (plan?['steps'] as List<dynamic>?) ?? [];
    final steps = rawSteps.map((s) {
      final stepMap = s as Map<String, dynamic>;
      final rawStatus = stepMap['status'] as String? ?? 'pending';
      final stepStatus = switch (rawStatus) {
        'running' || 'in_progress' => StepStatus.running,
        'completed' => StepStatus.completed,
        'failed' => StepStatus.failed,
        'skipped' => StepStatus.skipped,
        _ => StepStatus.pending,
      };
      return MissionStep(
        id: stepMap['id'] as String,
        title: stepMap['title'] as String,
        description: (stepMap['description'] as String?) ?? '',
        dependsOn: (stepMap['depends_on'] as List<dynamic>?)?.cast<String>() ?? [],
        expectedOutput: (stepMap['expected_output'] as String?) ?? '',
        status: stepStatus,
        errorMessage: stepMap['error_message'] as String?,
        resultText: stepMap['result_text'] as String?,
        completedAt: stepMap['completed_at'] != null
            ? DateTime.parse(stepMap['completed_at'] as String)
            : null,
      );
    }).toList();

    final rawClarifications = (map['clarifications'] as List<dynamic>?) ?? [];
    final clarifications = rawClarifications.map((q) {
      final qMap = q as Map<String, dynamic>;
      return ClarificationQuestion(
        id: qMap['id'] as String,
        question: qMap['question'] as String,
        answer: qMap['answer'] as String?,
      );
    }).toList();

    final statusStr = map['status'] as String? ?? 'draft';
    final status = switch (statusStr) {
      'needs_clarification' || 'needsClarification' => MissionStatus.needsClarification,
      'ready_for_approval' || 'readyForApproval' => MissionStatus.readyForApproval,
      'approved' => MissionStatus.approved,
      'running' || 'in_progress' => MissionStatus.running,
      'completed' => MissionStatus.completed,
      'failed' => MissionStatus.failed,
      'cancelled' => MissionStatus.cancelled,
      _ => MissionStatus.draft,
    };

    final rawArtifacts = (map['artifacts'] as List<dynamic>?) ?? [];
    final artifacts = rawArtifacts.map((a) {
      return MissionArtifact.fromMap(a as Map<String, dynamic>);
    }).toList();

    return Mission(
      id: map['id'] as String,
      objective: (map['goal'] as String?) ?? (map['objective'] as String? ?? ''),
      title: map['title'] as String? ?? 'Untitled Mission',
      status: status,
      steps: steps,
      clarifications: clarifications,
      artifacts: artifacts,
      resultSummary: map['result_summary'] as String?,
      failureReason: map['failure_reason'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : DateTime.now(),
      approvedByUser: (map['approved_by_user'] as bool?) ?? false,
    );
  }
}
