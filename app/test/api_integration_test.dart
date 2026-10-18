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

    test('Custom base URL can be set and takes precedence over default', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final config = ApiConfig(prefs);

      expect(config.baseUrl, isNotEmpty);
      await config.setBaseUrl('http://192.168.1.50:8000');
      expect(config.baseUrl, equals('http://192.168.1.50:8000'));
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
}
