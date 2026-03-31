import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_backend_client.dart';

class AiQuizService {
  // Types the backend `/ai/generate-questions` schema accepts directly.
  static const _backendSlotTypes = {
    'multiple_choice',
    'circle_answer',
    'fill_blank',
    'write_number',
    'true_false',
    'matching',
    'drag_drop',
  };

  // App-specific drag-drop subtypes → backend slot type mapping.
  // 'drag_drop_match' / 'drag_drop_order': matching left/right pairs
  //   → 'matching' produces similar verify-pair interactions from the model.
  // 'drag_drop_sequence' / 'drag_drop': fill-in-blanks in order
  //   → 'drag_drop' (generic sequence schema).
  // 'drag_drop_symbols' / 'drag_drop_compare': comparison placeholders
  //   → 'multiple_choice' (model cannot infer custom symbol widgets reliably).
  static const _slotTypeMap = <String, String>{
    'drag_drop_match': 'matching',
    'drag_drop_order': 'matching',
    'drag_drop_sequence': 'drag_drop',
    'drag_drop_symbols': 'multiple_choice',
    'drag_drop_compare': 'multiple_choice',
  };

  /// Builds slim remediation slots for `POST /ai/generate-questions`.
  ///
  /// App-specific drag-drop subtypes are mapped to the nearest supported
  /// backend schema type (see [_slotTypeMap]). Unknown types fall back to
  /// `multiple_choice` so the request never fails validation.
  static List<Map<String, dynamic>> buildRemediationSlots(
    List<Map<String, dynamic>> incorrect,
  ) {
    return incorrect.map((q) {
      final rawType = q['type']?.toString() ?? 'multiple_choice';
      final type = _backendSlotTypes.contains(rawType)
          ? rawType
          : (_slotTypeMap[rawType] ?? 'multiple_choice');
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
      final response = await AiBackendClient.postJson(
        '/ai/generate-questions',
        body: {
          'kind': 'remediation',
          'lessonId': lessonId,
          'lessonContext': lessonContext,
          'remediationSlots': remediationSlots,
          'originalIncorrectQuestions': originalIncorrectQuestions,
        },
        timeout: const Duration(seconds: 120),
      );

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
        if (data['requestId'] != null) 'requestId': data['requestId'].toString(),
        if (data['error'] != null) 'error': data['error'].toString(),
      };
    } catch (e) {
      debugPrint('AiQuizService.generateRemediationQuestions: $e');
      return {
        'success': false,
        'error': e.toString(),
        'questions': <Map<String, dynamic>>[],
      };
    }
  }

}
