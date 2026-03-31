import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Shared JSON POST helper for `/api/ai/*` routes (remediation, summaries, etc.).
class AiBackendClient {
  AiBackendClient._();

  /// [relativePath] must start with `/`, e.g. `/ai/generate-questions`.
  static Future<http.Response> postJson(
    String relativePath, {
    required Object body,
    Duration timeout = const Duration(seconds: 120),
  }) {
    final uri = Uri.parse('${ApiService.baseUrl}$relativePath');
    return http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
  }
}
