import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class AiQuizService {
  // #region agent log
  static Future<void> _agentDbg(
    String hypothesisId,
    String location,
    String message,
    Map<String, Object?> data,
  ) async {
    try {
      await http
          .post(
            Uri.parse(
              'http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',
            ),
            headers: {
              'Content-Type': 'application/json',
              'X-Debug-Session-Id': '78613b',
            },
            body: jsonEncode({
              'sessionId': '78613b',
              'hypothesisId': hypothesisId,
              'location': location,
              'message': message,
              'data': data,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(milliseconds: 1500));
    } catch (_) {}
  }
  // #endregion

  static Future<Map<String, dynamic>> generateQuiz({
    required String lessonId,
    required String lessonContext,
    required List<Map<String, dynamic>> incorrectQuestions,
  }) async {
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/ai/generate-quiz');
      // #region agent log
      await _agentDbg('H1_H3', 'ai_quiz_service.dart:prePost', 'before http.post', {
        'kIsWeb': kIsWeb,
        'defaultTargetPlatform': defaultTargetPlatform.name,
        'baseUrl': ApiService.baseUrl,
        'fullUri': uri.toString(),
        'incorrectCount': incorrectQuestions.length,
      });
      // #endregion
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
          .timeout(const Duration(seconds: 45));

      // #region agent log
      await _agentDbg('H2_H5', 'ai_quiz_service.dart:postOk', 'http response', {
        'statusCode': response.statusCode,
        'bodyLen': response.body.length,
      });
      // #endregion

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
      // #region agent log
      await _agentDbg('H1_H2_H3', 'ai_quiz_service.dart:catch', 'generateQuiz failed', {
        'errorType': e.runtimeType.toString(),
        'error': e.toString(),
      });
      // #endregion
      debugPrint('AiQuizService.generateQuiz: $e');
      return {
        'success': false,
        'error': e.toString(),
        'questions': <Map<String, dynamic>>[],
      };
    }
  }

  /// Normalizes AI multiple_choice items for Whole Numbers UI (numeric options, index correctAnswer).
  static List<Map<String, dynamic>> normalizeMultipleChoice(
    List<Map<String, dynamic>> raw,
  ) {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final q = raw[i];
      if (q['type'] != 'multiple_choice') continue;
      final opts = q['options'];
      if (opts is! List) continue;
      final options = <int>[];
      for (final o in opts) {
        if (o is int) {
          options.add(o);
        } else if (o is num) {
          options.add(o.toInt());
        }
      }
      if (options.length < 4 || options.length > 5) continue;
      final ca = q['correctAnswer'];
      int correct = 0;
      if (ca is int) {
        correct = ca;
      } else if (ca is num) {
        correct = ca.toInt();
      }
      if (correct < 0 || correct >= options.length) continue;
      final m = Map<String, dynamic>.from(q);
      m['id'] = i + 1;
      m['type'] = 'multiple_choice';
      m['options'] = options;
      m['correctAnswer'] = correct;
      if (q['objects'] is List) {
        m['objects'] = (q['objects'] as List).map((e) => e.toString()).toList();
      }
      if (q['objectCount'] is num) {
        m['objectCount'] = (q['objectCount'] as num).toInt();
      }
      out.add(m);
    }
    return out;
  }
}
