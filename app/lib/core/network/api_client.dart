import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HttpException;
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Structured error representing API and network failures (API_CONTRACT.md).
class ApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;
  final bool retryable;
  final String? correlationId;

  ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryable = false,
    this.correlationId,
  });

  @override
  String toString() => 'ApiException[$code]: $message (status: $statusCode)';
}

/// HTTP network client with correlation tracing, timeout enforcement,
/// session headers, and structured error normalization.
class ApiClient {
  final ApiConfig config;
  final http.Client _httpClient;
  final Duration timeout;

  ApiClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? http.Client();

  Map<String, String> _headers([Map<String, String>? extra]) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final correlationId = 'client_req_$now';
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Session-ID': config.sessionId,
      'X-Correlation-ID': correlationId,
      ...?extra,
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? queryParams]) {
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$base$cleanPath';
    final parsed = Uri.parse(fullUrl);
    if (queryParams != null && queryParams.isNotEmpty) {
      return parsed.replace(
        queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
      );
    }
    return parsed;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParams}) async {
    return _send(() => _httpClient.get(_uri(path, queryParams), headers: _headers()));
  }

  Future<dynamic> post(String path, {dynamic body}) async {
    final encoded = body != null ? jsonEncode(body) : null;
    return _send(() => _httpClient.post(_uri(path), headers: _headers(), body: encoded));
  }

  Future<dynamic> _send(Future<http.Response> Function() requestFn) async {
    try {
      final response = await requestFn().timeout(timeout);
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        code: 'TIMEOUT',
        message: 'The request to the Tusk.ai backend timed out. Please retry.',
        retryable: true,
      );
    } on SocketException {
      throw ApiException(
        code: 'NETWORK_UNAVAILABLE',
        message: 'Unable to reach the Tusk.ai backend (${config.baseUrl}). Verify server is running.',
        retryable: true,
      );
    } on HttpException catch (e) {
      throw ApiException(
        code: 'HTTP_ERROR',
        message: 'Network connection issue: ${e.message}',
        retryable: true,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        code: 'CLIENT_ERROR',
        message: 'An unexpected connection error occurred: $e',
        retryable: true,
      );
    }
  }

  dynamic _handleResponse(http.Response response) {
    dynamic jsonBody;
    try {
      if (response.body.isNotEmpty) {
        jsonBody = jsonDecode(response.body);
      }
    } catch (_) {
      // Body not valid JSON
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonBody ?? response.body;
    }

    // Parse structured backend error matching API_CONTRACT.md
    if (jsonBody is Map<String, dynamic> && jsonBody.containsKey('error')) {
      final err = jsonBody['error'] as Map<String, dynamic>;
      throw ApiException(
        code: (err['code'] as String?) ?? 'API_ERROR',
        message: (err['message'] as String?) ?? 'An error occurred.',
        statusCode: response.statusCode,
        retryable: (err['retryable'] as bool?) ?? false,
        correlationId: err['correlation_id'] as String?,
      );
    }

    throw ApiException(
      code: 'HTTP_${response.statusCode}',
      message: 'Server returned error status ${response.statusCode}.',
      statusCode: response.statusCode,
      retryable: response.statusCode >= 500,
    );
  }

  void close() {
    _httpClient.close();
  }
}
