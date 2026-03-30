import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senyamatika_math_app/features/exercise/controller/exercise_controller.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/exercise_header.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/question_display.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/exercise_results_screen.dart';

/// Single configurable exercise screen.
///
/// Replaces the 7 duplicated `*ExerciseScreen` classes that previously lived
/// in `main.dart`. Call it from the navigation layer with the topic-specific
/// [questions] list and an [onRecordScore] closure that persists the result
/// via [ProgressManager].
///
/// When [autoStartRemediation] is true (and [showAiRemediation] is true), the
/// controller immediately generates AI questions before showing any content,
/// so returning users who have never passed are redirected to an AI quiz.
///
/// Example:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => ExerciseScreen(
///       lessonName: 'Whole Numbers',
///       language: 'English',
///       title: 'Whole Numbers Exercise',
///       questions: WholeNumbersQuestions.all,
///       showAiRemediation: true,
///       onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>
///           progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),
///     ),
///   ),
/// );
/// ```
class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({
    super.key,
    required this.lessonName,
    required this.language,
    required this.title,
    required this.questions,
    required this.onRecordScore,
    this.allLessonNames,
    this.showAiRemediation = false,
    this.autoStartRemediation = false,
    this.lessonId,
    this.aiLessonContext,
  });

  final String lessonName;
  final String language;
  final String title;
  final List<Map<String, dynamic>> questions;
  final RecordScoreCallback onRecordScore;

  /// When non-null, score is recorded under all names in this list.
  /// Used by the Fundamental Operations exercise (covers 4 lessons).
  final List<String>? allLessonNames;

  /// Enables AI remediation: "Try Again" generates AI questions on failure,
  /// and [autoStartRemediation] auto-generates on entry when true.
  final bool showAiRemediation;

  /// When [true] and [showAiRemediation] is also true, AI question generation
  /// starts immediately (before any questions are shown). The user sees a
  /// loading screen while generation runs. Use this for users who have
  /// previously attempted the exercise but have never passed.
  final bool autoStartRemediation;

  /// Lesson identifier passed to the AI service.
  final String? lessonId;

  /// Pre-built lesson context map for the AI service.
  final Map<String, dynamic>? aiLessonContext;

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  late final ExerciseController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ExerciseController(
      lessonName: widget.lessonName,
      language: widget.language,
      exerciseTitle: widget.title,
      questions: widget.questions,
      onRecordScore: widget.onRecordScore,
      allLessonNames: widget.allLessonNames,
      showAiRemediation: widget.showAiRemediation,
      autoStartRemediation: widget.autoStartRemediation,
      lessonId: widget.lessonId,
      aiLessonContext: widget.aiLessonContext,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showAiError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ExerciseController>.value(
      value: _controller,
      child: Consumer<ExerciseController>(
        builder: (context, controller, _) {
          // Loading screen while AI generates questions on entry
          if (controller.aiQuizLoading) {
            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                centerTitle: true,
                elevation: 0,
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          // Switch to results view once all questions are answered
          if (controller.exerciseCompleted) {
            return ExerciseResultsScreen(
              exerciseTitle: widget.title,
              onAiError: _showAiError,
            );
          }

          final sw = MediaQuery.of(context).size.width;
          final q = controller.questions[controller.currentQuestion];
          final isAnswered =
              controller.answeredQuestions[controller.currentQuestion];
          final isLast =
              controller.currentQuestion == controller.questions.length - 1;

          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              centerTitle: true,
              elevation: 0,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: sw * 0.04,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    ExerciseHeader(
                      currentQuestion: controller.currentQuestion,
                      totalQuestions: controller.questions.length,
                      questionType: q['type'] as String,
                      score: controller.score,
                    ),
                    const SizedBox(height: 20),

                    const QuestionDisplay(),

                    const SizedBox(height: 20),

                    // ── Navigation buttons ──────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                                side: const BorderSide(
                                    color: Colors.black, width: 1),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 1,
                            ),
                            onPressed: controller.currentQuestion > 0
                                ? controller.previousQuestion
                                : null,
                            child: const Text('Previous',
                                style: TextStyle(fontSize: 15)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFF59D),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                                side: const BorderSide(
                                    color: Colors.black, width: 1),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 1,
                            ),
                            onPressed: isAnswered
                                ? (isLast
                                    ? controller.finishExercise
                                    : controller.nextQuestion)
                                : null,
                            child: Text(
                              isLast ? 'Finish' : 'Next',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
