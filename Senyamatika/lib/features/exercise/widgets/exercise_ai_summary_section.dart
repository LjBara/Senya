import 'package:flutter/material.dart';

import 'package:senyamatika_math_app/backend/services/exercise_summary_service.dart';
import 'package:senyamatika_math_app/features/exercise/ai/exercise_ai_policy.dart';

/// Loads an English AI recap once via [ExerciseSummaryService] and shows
/// summary text plus recommended subtopics, with loading and error fallbacks.
class ExerciseAiSummarySection extends StatefulWidget {
  const ExerciseAiSummarySection({
    super.key,
    required this.lessonId,
    required this.lessonContext,
    required this.exerciseTitle,
    required this.score,
    required this.totalQuestions,
    required this.wrongQuestions,
    required this.lessonNamesForInsights,
    this.onInsightsSaved,
  });

  final String lessonId;
  final Map<String, dynamic> lessonContext;
  final String exerciseTitle;
  final int score;
  final int totalQuestions;
  final List<Map<String, dynamic>> wrongQuestions;

  /// Hive / progress keys to store [onInsightsSaved] under (see ProgressManager).
  final List<String> lessonNamesForInsights;

  /// Called once when the API returns a non-empty recap (for My Progress Insights).
  final ExerciseInsightsSavedCallback? onInsightsSaved;

  @override
  State<ExerciseAiSummarySection> createState() =>
      _ExerciseAiSummarySectionState();
}

class _ExerciseAiSummarySectionState extends State<ExerciseAiSummarySection> {
  late final Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ExerciseSummaryService.requestExerciseSummary(
      lessonId: widget.lessonId,
      lessonContext: widget.lessonContext,
      exerciseTitle: widget.exerciseTitle,
      score: widget.score,
      totalQuestions: widget.totalQuestions,
      wrongQuestions: widget.wrongQuestions,
    ).then((data) {
      if (!mounted) return data;
      if (data['success'] == true && widget.onInsightsSaved != null) {
        final summary = (data['summary'] as String?)?.trim() ?? '';
        final rawTopics = data['recommendedSubtopics'];
        final topics = <String>[];
        if (rawTopics is List) {
          for (final e in rawTopics) {
            final s = e?.toString().trim();
            if (s != null && s.isNotEmpty) topics.add(s);
          }
        }
        if (summary.isNotEmpty || topics.isNotEmpty) {
          widget.onInsightsSaved!(
            widget.lessonNamesForInsights,
            summary,
            topics,
          );
        }
      }
      return data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black26),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Getting your personalized summary…',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return _fallbackLine(
            'We could not load your study tips. You can still review the lesson anytime.',
          );
        }

        if (data['success'] != true) {
          return _fallbackLine(
            'We could not load your study tips. You can still review the lesson anytime.',
          );
        }

        final summary = (data['summary'] as String?)?.trim() ?? '';
        final rawTopics = data['recommendedSubtopics'];
        final topics = <String>[];
        if (rawTopics is List) {
          for (final e in rawTopics) {
            final s = e?.toString().trim();
            if (s != null && s.isNotEmpty) topics.add(s);
          }
        }

        if (summary.isEmpty && topics.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How you did',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    summary,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                ],
                if (topics.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Suggested review',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...topics.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(fontSize: 15)),
                          Expanded(
                            child: Text(
                              t,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackLine(String message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade700,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
