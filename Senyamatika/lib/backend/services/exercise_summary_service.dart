import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_backend_client.dart';

/// Client for `POST /api/ai/exercise-summary` (English recap + subtopic hints).
class ExerciseSummaryService {
  ExerciseSummaryService._();

  static const Duration _timeout = Duration(seconds: 60);

  /// Returns a map with `success`, optional `summary`, `recommendedSubtopics`,
  /// `error`, and `requestId` (mirrors remediation response style).
  static Future<Map<String, dynamic>> requestExerciseSummary({
    required String lessonId,
    required Map<String, dynamic> lessonContext,
    required String exerciseTitle,
    required int score,
    required int totalQuestions,
    required List<Map<String, dynamic>> wrongQuestions,
  }) async {
    try {
      final response = await AiBackendClient.postJson(
        '/ai/exercise-summary',
        body: {
          'lessonId': lessonId,
          'lessonContext': Map<String, dynamic>.from(lessonContext),
          'exerciseTitle': exerciseTitle,
          'score': score,
          'totalQuestions': totalQuestions,
          'wrongQuestions': wrongQuestions,
        },
        timeout: _timeout,
      );

      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        data = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{'raw': decoded};
      } catch (e) {
        return {
          'success': false,
          'error': 'Invalid JSON: $e',
        };
      }

      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': data['error']?.toString() ?? 'Request failed',
          if (data['requestId'] != null)
            'requestId': data['requestId'].toString(),
        };
      }

      final ok = data['success'] == true;
      if (!ok) {
        return {
          'success': false,
          'error': data['error']?.toString() ?? 'Summary unavailable',
          if (data['requestId'] != null)
            'requestId': data['requestId'].toString(),
        };
      }

      final summary = data['summary']?.toString() ?? '';
      final rawTopics = data['recommendedSubtopics'];
      final topics = <String>[];
      if (rawTopics is List) {
        for (final e in rawTopics) {
          if (e != null) topics.add(e.toString());
        }
      }

      return {
        'success': true,
        'summary': summary,
        'recommendedSubtopics': topics,
        if (data['requestId'] != null)
          'requestId': data['requestId'].toString(),
      };
    } catch (e) {
      debugPrint('ExerciseSummaryService.requestExerciseSummary: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
