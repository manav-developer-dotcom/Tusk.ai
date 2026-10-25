import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tusk_ai/core/network/api_client.dart';
import 'package:tusk_ai/core/network/api_config.dart';
import 'package:tusk_ai/features/mission/models/mission.dart';
import 'package:tusk_ai/features/mission/services/mission_api_service.dart';
import 'package:tusk_ai/features/mission/services/mission_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiConfig Tests', () {
    test('Session ID is generated once and persisted across lookups', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final session1 = config.sessionId;
      expect(session1.startsWith('session_'), isTrue);

      final session2 = config.sessionId;
      expect(session2, equals(session1));
    });

    test('Default base URL resolves platform fallback or env default correctly', () {
      final defaultUrl = ApiConfig.resolveDefaultBaseUrl();
      expect(defaultUrl, isNotEmpty);
      expect(defaultUrl.startsWith('http://') || defaultUrl.startsWith('https://'), isTrue);
    });

    test('Presets contain valid URLs including defaultLanBaseUrl, emulatorBaseUrl, and localHostBaseUrl', () {
      expect(ApiConfig.presets.length, equals(3));
      expect(ApiConfig.presets.any((p) => p.url == ApiConfig.defaultLanBaseUrl), isTrue);
      expect(ApiConfig.presets.any((p) => p.url == ApiConfig.emulatorBaseUrl), isTrue);
      expect(ApiConfig.presets.any((p) => p.url == ApiConfig.localHostBaseUrl), isTrue);
      for (final preset in ApiConfig.presets) {
        expect(ApiConfig.isValidUrl(preset.url), isTrue);
      }
    });

    test('URL normalization handles bare host:port and trailing slashes', () {
      expect(ApiConfig.normalizeBaseUrl('192.168.0.110:8000'), equals('http://192.168.0.110:8000'));
      expect(ApiConfig.normalizeBaseUrl('http://192.168.0.110:8000///'), equals('http://192.168.0.110:8000'));
      expect(ApiConfig.normalizeBaseUrl('https://api.tusk.ai/'), equals('https://api.tusk.ai'));
      expect(ApiConfig.normalizeBaseUrl(''), equals(''));
    });

    test('URL validation accepts valid HTTP/HTTPS URLs and rejects invalid inputs', () {
      expect(ApiConfig.isValidUrl('http://192.168.0.110:8000'), isTrue);
      expect(ApiConfig.isValidUrl('192.168.0.110:8000'), isTrue);
      expect(ApiConfig.isValidUrl('https://api.tusk.ai:8000'), isTrue);
      expect(ApiConfig.isValidUrl(''), isFalse);
      expect(ApiConfig.isValidUrl('   '), isFalse);
    });

    test('Custom base URL can be set, normalized, persisted, and updates isCustomBaseUrl', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      expect(config.isCustomBaseUrl, isFalse);
      await config.setBaseUrl('192.168.0.110:8000');
      expect(config.baseUrl, equals('http://192.168.0.110:8000'));
      expect(config.isCustomBaseUrl, isTrue);
    });

    test('Resetting base URL restores platform default and clears custom flag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      await config.setBaseUrl('http://192.168.0.110:8000');
      expect(config.isCustomBaseUrl, isTrue);

      await config.resetBaseUrl();
      expect(config.isCustomBaseUrl, isFalse);
      expect(config.baseUrl, equals(ApiConfig.resolveDefaultBaseUrl()));
    });

    test('ApiConfig notifies listeners on setBaseUrl and resetBaseUrl', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      int notifications = 0;
      config.addListener(() => notifications++);

      await config.setBaseUrl('http://192.168.0.110:8000');
      expect(notifications, equals(1));

      await config.resetBaseUrl();
      expect(notifications, equals(2));
    });

    test('ApiClient dynamically targets updated baseUrl without client re-instantiation', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      late String requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response('{"status":"healthy"}', 200, headers: {'content-type': 'application/json'});
      });

      final client = ApiClient(config: config, httpClient: mockClient);

      await client.get('/health');
      expect(requestedUrl, equals('${ApiConfig.resolveDefaultBaseUrl()}/health'));

      await config.setBaseUrl('http://192.168.0.110:8000');
      await client.get('/health');
      expect(requestedUrl, equals('http://192.168.0.110:8000/health'));
    });
  });


  group('ApiClient Error & Header Handling Tests', () {
    test('Headers include X-Session-ID, X-Correlation-ID and Content-Type', () async {
      SharedPreferences.setMockInitialValues({'tusk_anonymous_session_v1': 'test_session_xyz'});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      late Map<String, String> capturedHeaders;
      final mockClient = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response('{"status":"ok"}', 200, headers: {'content-type': 'application/json'});
      });

      final client = ApiClient(config: config, httpClient: mockClient);
      final res = await client.get('/test');

      expect(res, equals({'status': 'ok'}));
      expect(capturedHeaders['X-Session-ID'], equals('test_session_xyz'));
      expect(capturedHeaders['X-Correlation-ID'], startsWith('client_req_'));
      expect(capturedHeaders['Content-Type'], equals('application/json'));
    });

    test('Structured API errors are parsed into ApiException', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {
              'code': 'INVALID_STATE_TRANSITION',
              'message': 'Mission cannot transition from completed to in_progress',
              'correlation_id': 'corr-abc-123',
              'retryable': false,
            }
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(config: config, httpClient: mockClient);

      expect(
        () => client.post('/v1/missions/m1/approve'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'INVALID_STATE_TRANSITION')
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.retryable, 'retryable', false)
            .having((e) => e.correlationId, 'correlationId', 'corr-abc-123')),
      );
    });
  });

  group('MissionApiService Tests', () {
    test('checkHealth returns true on healthy and false on failure', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final healthyClient = ApiClient(
        config: config,
        httpClient: MockClient((req) async => http.Response('{"status":"healthy"}', 200)),
      );
      final unhealthyClient = ApiClient(
        config: config,
        httpClient: MockClient((req) async => http.Response('Internal Error', 500)),
      );

      final serviceHealthy = MissionApiService(healthyClient);
      final serviceUnhealthy = MissionApiService(unhealthyClient);

      expect(await serviceHealthy.checkHealth(), isTrue);
      expect(await serviceUnhealthy.checkHealth(), isFalse);
    });

    test('createMission parses full mission and steps correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final mockBackendResponse = {
        'id': 'msn_12345678',
        'goal': 'Write marketing copy for Tusk.ai launch',
        'title': 'Draft Launch Copy',
        'status': 'ready_for_approval',
        'approved_by_user': false,
        'plan': {
          'steps': [
            {
              'id': 'step-1',
              'title': 'Outline value proposition',
              'description': 'Identify key benefits',
              'depends_on': [],
              'status': 'pending',
              'expected_output': 'List of benefits',
            },
            {
              'id': 'step-2',
              'title': 'Draft body text',
              'description': 'Expand on benefits',
              'depends_on': ['step-1'],
              'status': 'pending',
              'expected_output': 'Full draft',
            }
          ]
        },
        'clarifications': [],
        'artifacts': [],
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final client = ApiClient(
        config: config,
        httpClient: MockClient((req) async => http.Response(
          jsonEncode(mockBackendResponse),
          201,
          headers: {'content-type': 'application/json'},
        )),
      );

      final service = MissionApiService(client);
      final mission = await service.createMission(
        goal: 'Write marketing copy for Tusk.ai launch',
        conversationId: 'conv_abc',
      );

      expect(mission.id, equals('msn_12345678'));
      expect(mission.title, equals('Draft Launch Copy'));
      expect(mission.status, equals(MissionStatus.readyForApproval));
      expect(mission.steps.length, equals(2));
      expect(mission.steps.first.title, equals('Outline value proposition'));
      expect(mission.conversationId, equals('conv_abc'));
    });

    test('approve, cancel, and retry endpoints parse updated mission status', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final mockClient = MockClient((req) async {
        if (req.url.path.endsWith('/approve')) {
          return http.Response(
            jsonEncode({
              'id': 'msn_test',
              'goal': 'Goal',
              'title': 'Title',
              'status': 'ready_for_approval',
              'approved_by_user': true,
              'plan': {'steps': []},
              'clarifications': [],
            }),
            200,
          );
        } else if (req.url.path.endsWith('/cancel')) {
          return http.Response(
            jsonEncode({
              'id': 'msn_test',
              'goal': 'Goal',
              'title': 'Title',
              'status': 'cancelled',
              'failure_reason': 'Cancelled by user.',
              'plan': {'steps': []},
              'clarifications': [],
            }),
            200,
          );
        } else if (req.url.path.endsWith('/retry')) {
          return http.Response(
            jsonEncode({
              'id': 'msn_test',
              'goal': 'Goal',
              'title': 'Title',
              'status': 'ready_for_approval',
              'approved_by_user': false,
              'plan': {'steps': []},
              'clarifications': [],
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = MissionApiService(ApiClient(config: config, httpClient: mockClient));

      final approved = await service.approveMission('msn_test');
      expect(approved.approvedByUser, isTrue);

      final cancelled = await service.cancelMission('msn_test');
      expect(cancelled.status, equals(MissionStatus.cancelled));

      final retried = await service.retryMission('msn_test');
      expect(retried.status, equals(MissionStatus.readyForApproval));
    });
  });

  group('MissionRepository Dual Cache & Sync Tests', () {
    test('Repository syncs remote missions into local persistent storage', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final mockMissions = [
        {
          'id': 'remote_1',
          'goal': 'Sync test goal',
          'title': 'Remote Mission',
          'status': 'in_progress',
          'plan': {'steps': []},
          'clarifications': [],
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }
      ];

      final client = ApiClient(
        config: config,
        httpClient: MockClient((req) async => http.Response(
          jsonEncode({'missions': mockMissions, 'total': 1}),
          200,
        )),
      );

      final apiService = MissionApiService(client);
      final repo = MissionRepository(prefs, apiService: apiService);

      final synced = await repo.syncRemoteMissions();
      expect(synced.length, equals(1));
      expect(synced.first.id, equals('remote_1'));

      // Verify that mission is now stored in local cache and readable offline
      final cached = repo.loadMission('remote_1');
      expect(cached, isNotNull);
      expect(cached!.title, equals('Remote Mission'));
    });
  });

  group('Phase 4 — Execute, Artifacts, Content Tests', () {
    test('executeMission parses completed mission with steps', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final completedMission = {
        'id': 'msn_exec_01',
        'goal': 'Launch campaign for Tusk.ai',
        'title': 'Launch Campaign',
        'status': 'completed',
        'approved_by_user': true,
        'plan': {
          'steps': [
            {
              'id': 'msn_exec_01_step_1',
              'title': 'Marketing strategy',
              'description': 'Define target audience',
              'depends_on': [],
              'status': 'completed',
              'expected_output': 'Strategy doc',
              'result_text': 'Strategy created successfully.',
            }
          ]
        },
        'clarifications': [],
        'artifacts': [
          {
            'id': 'art_abc123',
            'mission_id': 'msn_exec_01',
            'step_id': 'msn_exec_01_step_1',
            'media_type': 'text/markdown',
            'name': 'launch_campaign_deliverables.md',
            'size_bytes': 9802,
            'url': null,
            'created_at': DateTime.now().toIso8601String(),
          }
        ],
        'result_summary': 'Campaign deliverables ready.',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final client = ApiClient(
        config: config,
        httpClient: MockClient((req) async => http.Response(
          jsonEncode(completedMission),
          200,
          headers: {'content-type': 'application/json'},
        )),
      );

      final service = MissionApiService(client);
      final mission = await service.executeMission('msn_exec_01');

      expect(mission.id, equals('msn_exec_01'));
      expect(mission.status, equals(MissionStatus.completed));
      expect(mission.steps.first.status, equals(StepStatus.completed));
      expect(mission.steps.first.resultText, equals('Strategy created successfully.'));
      expect(mission.artifacts.length, equals(1));
      expect(mission.artifacts.first.name, equals('launch_campaign_deliverables.md'));
      expect(mission.artifacts.first.sizeBytes, equals(9802));
      expect(mission.resultSummary, equals('Campaign deliverables ready.'));
    });

    test('listArtifacts returns parsed artifact list', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      final artifactList = {
        'artifacts': [
          {
            'id': 'art_111',
            'mission_id': 'msn_001',
            'step_id': null,
            'media_type': 'text/markdown',
            'name': 'report.md',
            'size_bytes': 1024,
            'url': null,
            'created_at': DateTime.now().toIso8601String(),
          }
        ]
      };

      final client = ApiClient(
        config: config,
        httpClient: MockClient((req) async => http.Response(
          jsonEncode(artifactList),
          200,
          headers: {'content-type': 'application/json'},
        )),
      );

      final service = MissionApiService(client);
      final artifacts = await service.listArtifacts('msn_001');

      expect(artifacts.length, equals(1));
      expect(artifacts.first.id, equals('art_111'));
      expect(artifacts.first.name, equals('report.md'));
      expect(artifacts.first.sizeBytes, equals(1024));
    });

    test('getArtifactContent returns plain text body', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      const markdownBody = '# Campaign\n\nThis is the content.';

      final client = ApiClient(
        config: config,
        httpClient: MockClient((req) async => http.Response(
          markdownBody,
          200,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        )),
      );

      final service = MissionApiService(client);
      final content = await service.getArtifactContent('art_111');

      expect(content, equals(markdownBody));
    });

    test('MissionRepository.executeMission delegates to apiService and caches result', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      // Pre-seed a local mission with a conversationId to verify it is preserved.
      final existingMission = Mission(
        id: 'msn_repo_exec',
        objective: 'Exec test',
        title: 'Exec Test',
        conversationId: 'conv_preserved',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: MissionStatus.approved,
      );

      final repo = MissionRepository(prefs);
      await repo.saveMission(existingMission);

      final completedPayload = {
        'id': 'msn_repo_exec',
        'goal': 'Exec test',
        'title': 'Exec Test',
        'status': 'completed',
        'approved_by_user': true,
        'plan': {'steps': []},
        'clarifications': [],
        'artifacts': [
          {
            'id': 'art_repo_1',
            'mission_id': 'msn_repo_exec',
            'step_id': null,
            'media_type': 'text/markdown',
            'name': 'output.md',
            'size_bytes': 512,
            'url': null,
            'created_at': DateTime.now().toIso8601String(),
          }
        ],
        'result_summary': 'Done.',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final artifactsPayload = {
        'artifacts': [
          {
            'id': 'art_repo_1',
            'mission_id': 'msn_repo_exec',
            'step_id': null,
            'media_type': 'text/markdown',
            'name': 'output.md',
            'size_bytes': 512,
            'url': null,
            'created_at': DateTime.now().toIso8601String(),
          }
        ]
      };

      final client = ApiClient(
        config: config,
        httpClient: MockClient((req) async {
          if (req.url.path.endsWith('/artifacts')) {
            return http.Response(
              jsonEncode(artifactsPayload),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode(completedPayload),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final repoWithApi = MissionRepository(prefs, apiService: MissionApiService(client));
      // Save the seeded mission into this new repo instance too
      await repoWithApi.saveMission(existingMission);

      final updated = await repoWithApi.executeMission('msn_repo_exec');

      expect(updated, isNotNull);
      expect(updated!.status, equals(MissionStatus.completed));
      expect(updated.conversationId, equals('conv_preserved'));
      expect(updated.artifacts.length, equals(1));
      expect(updated.artifacts.first.name, equals('output.md'));

      // Verify the result was persisted in local cache
      final cached = repoWithApi.loadMission('msn_repo_exec');
      expect(cached?.status, equals(MissionStatus.completed));
    });
  });
}
