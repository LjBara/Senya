import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AiQuizService {
  // #region agent log
  static void _dbgIngest(String location, String message, Map<String, Object?> data) {
    try {
      final base = Uri.parse(ApiService.baseUrl);
      final ingest = Uri(
        scheme: base.scheme.isEmpty ? 'http' : base.scheme,
        host: base.host,
        port: 7383,
        path: '/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',
      );
      http
          .post(
            ingest,
            headers: {
              'Content-Type': 'application/json',
              'X-Debug-Session-Id': 'df25fd',
            },
            body: jsonEncode({
              'sessionId': 'df25fd',
              'runId': 'pre-fix',
              'hypothesisId': 'H-flutter',
              'location': location,
              'message': message,
              'data': data,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(milliseconds: 600));
    } catch (_) {}
  }
  // #endregion

  static const _knownSlotTypes = {
    'multiple_choice',
    'circle_answer',
    'fill_blank',
    'write_number',
    'true_false',
    'matching',
    'drag_drop',
  };

  /// Slim remediation slots for `POST /ai/generate-questions` (aligned with backend zod).
  static List<Map<String, dynamic>> buildRemediationSlots(
    List<Map<String, dynamic>> incorrect,
  ) {
    return incorrect.map((q) {
      final rawType = q['type']?.toString() ?? 'multiple_choice';
      final type =
          _knownSlotTypes.contains(rawType) ? rawType : 'multiple_choice';
      final question = q['question']?.toString() ?? '';
      final summary =
          question.length > 500 ? question.substring(0, 500) : question;
      final slot = <String, dynamic>{
        'type': type,
        'summary': summary.isEmpty ? '(no summary)' : summary,
      };
      final oc = q['objectCount'];
      if (oc is num) {
        slot['objectCountHint'] = oc.toInt();
      }
      return slot;
    }).toList();
  }

  /// Structured lesson context merged with DB on the server.
  static Map<String, dynamic> buildLessonContextMap({
    required String lessonTitle,
    String? topicId,
    List<String> subtopics = const [],
  }) {
    return {
      if (topicId != null && topicId.isNotEmpty) 'topicId': topicId,
      'lessonTitle': lessonTitle,
      if (subtopics.isNotEmpty) 'subtopics': subtopics,
    };
  }

  /// Primary path: `POST /api/ai/generate-questions` (remediation, typed output, server validation).
  static Future<Map<String, dynamic>> generateRemediationQuestions({
    required String lessonId,
    required Map<String, dynamic> lessonContext,
    required List<Map<String, dynamic>> remediationSlots,
    required List<Map<String, dynamic>> originalIncorrectQuestions,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/ai/generate-questions');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'kind': 'remediation',
              'lessonId': lessonId,
              'lessonContext': lessonContext,
              'remediationSlots': remediationSlots,
              'originalIncorrectQuestions': originalIncorrectQuestions,
            }),
          )
          .timeout(const Duration(seconds: 120));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // #region agent log
      final rawForLen = data['questions'];
      final qLen = rawForLen is List ? rawForLen.length : -1;
      final errStr = data['error']?.toString() ?? '';
      final errPreview =
          errStr.length > 120 ? '${errStr.substring(0, 120)}...' : errStr;
      _dbgIngest('ai_quiz_service.dart:generateRemediationQuestions', 'response', {
        'statusCode': response.statusCode,
        'bodyLen': response.body.length,
        'questionsLen': qLen,
        'successField': data['success']?.toString() ?? 'null',
        'errPreview': errPreview,
      });
      // #endregion
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': data['error']?.toString() ?? 'Request failed',
          'questions': <Map<String, dynamic>>[],
        };
      }

      final raw = data['questions'];
      if (raw is! List) {
        return {
          'success': false,
          'error': 'Invalid response: questions is not a list',
          'questions': <Map<String, dynamic>>[],
        };
      }

      final questions = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          questions.add(Map<String, dynamic>.from(item));
        }
      }

      return {
        'success': data['success'] == true,
        'questions': questions,
        'fallback': data['fallback'] == true,
        if (data['requestId'] != null) 'requestId': data['requestId'].toString(),
        if (data['error'] != null) 'error': data['error'].toString(),
      };
    } catch (e) {
      // #region agent log
      _dbgIngest('ai_quiz_service.dart:generateRemediationQuestions', 'catch', {
        'err': e.toString(),
      });
      // #endregion
      debugPrint('AiQuizService.generateRemediationQuestions: $e');
      return {
        'success': false,
        'error': e.toString(),
        'questions': <Map<String, dynamic>>[],
      };
    }
  }

  /// Legacy `POST /api/ai/generate-quiz` (string context); kept for older builds / tools.
  static Future<Map<String, dynamic>> generateQuiz({
    required String lessonId,
    required String lessonContext,
    required List<Map<String, dynamic>> incorrectQuestions,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/ai/generate-quiz');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'lessonId': lessonId,
              'lessonContext': lessonContext,
              'incorrectQuestions': incorrectQuestions,
            }),
          )
          .timeout(const Duration(seconds: 120));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': data['error']?.toString() ?? 'Request failed',
          'questions': <Map<String, dynamic>>[],
        };
      }

      final raw = data['questions'];
      if (raw is! List) {
        return {
          'success': false,
          'error': 'Invalid response: questions is not a list',
          'questions': <Map<String, dynamic>>[],
        };
      }

      final questions = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          questions.add(Map<String, dynamic>.from(item));
        }
      }

      return {
        'success': data['success'] == true,
        'questions': questions,
        'fallback': data['fallback'] == true,
        if (data['error'] != null) 'error': data['error'].toString(),
      };
    } catch (e) {
      debugPrint('AiQuizService.generateQuiz: $e');
      return {
        'success': false,
        'error': e.toString(),
        'questions': <Map<String, dynamic>>[],
      };
    }
  }
}
