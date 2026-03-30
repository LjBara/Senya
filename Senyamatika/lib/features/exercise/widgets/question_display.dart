import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senyamatika_math_app/features/exercise/controller/exercise_controller.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/question_type/mc_question_widget.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/question_type/fill_blank_widget.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/question_type/true_false_widget.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/question_type/matching_widget.dart';
import 'package:senyamatika_math_app/features/exercise/widgets/question_type/drag_drop_widget.dart';

/// Reads the current question from [ExerciseController] and delegates
/// rendering to the correct question-type widget.
///
/// Also renders the feedback banner (correct / incorrect + explanation)
/// and the "Submit Answer" button for interactive question types.
class QuestionDisplay extends StatelessWidget {
  const QuestionDisplay({super.key});

  static bool _requiresSubmitButton(String type) {
    return type == 'matching' || type.startsWith('drag_drop');
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExerciseController>();
    final sw = MediaQuery.of(context).size.width;

    final q = controller.questions[controller.currentQuestion];
    final type = q['type'] as String;
    final isAnswered = controller.answeredQuestions[controller.currentQuestion];
    final userAnswer = controller.userAnswers[controller.currentQuestion];

    return Column(
      children: [
        // ── Question card ─────────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(sw * 0.05),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(4, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                q['question'] as String,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: sw * 0.045,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),

              // ── Question-type widget ───────────────────────────────────
              _buildTypeWidget(context, controller, q, type, isAnswered, userAnswer, sw),

              const SizedBox(height: 12),

              // ── Submit button for interactive types ────────────────────
              if (!isAnswered && _requiresSubmitButton(type))
                _SubmitButton(
                  onPressed: controller.isInteractiveComplete()
                      ? controller.submitInteractiveAnswer
                      : null,
                ),

              // ── Feedback banner ────────────────────────────────────────
              if (isAnswered) ...[
                const SizedBox(height: 8),
                _FeedbackBanner(
                  isCorrect: controller.isAnswerCorrectAt(controller.currentQuestion),
                  explanation: q['explanation']?.toString() ?? '',
                  screenWidth: sw,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeWidget(
    BuildContext context,
    ExerciseController controller,
    Map<String, dynamic> q,
    String type,
    bool isAnswered,
    dynamic userAnswer,
    double sw,
  ) {
    switch (type) {
      case 'multiple_choice':
        return McQuestionWidget(
          question: q,
          isAnswered: isAnswered,
          userAnswer: userAnswer,
          onAnswer: controller.answerQuestion,
        );

      case 'circle_answer':
        return McQuestionWidget(
          question: q,
          isAnswered: isAnswered,
          userAnswer: userAnswer,
          onAnswer: controller.answerQuestion,
          circleStyle: true,
        );

      case 'fill_blank':
        return FillBlankWidget(
          key: ValueKey(controller.currentQuestion),
          isAnswered: isAnswered,
          userAnswer: userAnswer,
          onAnswer: controller.answerQuestion,
        );

      case 'write_number':
        return FillBlankWidget(
          key: ValueKey(controller.currentQuestion),
          isAnswered: isAnswered,
          userAnswer: userAnswer,
          onAnswer: controller.answerQuestion,
          numericOnly: true,
        );

      case 'true_false':
        return TrueFalseWidget(
          isAnswered: isAnswered,
          userAnswer: userAnswer,
          correctAnswer: q['correctAnswer'] as bool,
          onAnswer: controller.answerQuestion,
        );

      case 'matching':
        return MatchingWidget(
          question: q,
          isAnswered: isAnswered,
          selections: controller.currentMatchingSelections,
          onSelectionChanged: controller.updateMatchingSelection,
        );

      case 'drag_drop':
      case 'drag_drop_order':
      case 'drag_drop_symbols':
      case 'drag_drop_sequence':
      case 'drag_drop_compare':
      case 'drag_drop_match':
        if (!controller.dragItemsInitialized) return const SizedBox.shrink();
        return DragDropWidget(
          question: q,
          dragItems: controller.dragItems,
          filledBlanks: type == 'drag_drop_sequence' || type == 'drag_drop'
              ? controller.currentSequenceFilledBlanks
              : controller.currentMatchFilledBlanks,
          comparePlacedSymbol: controller.currentComparePlacedSymbol,
          isAnswered: isAnswered,
          onFillBlank: type == 'drag_drop_sequence' || type == 'drag_drop'
              ? controller.updateSequenceBlank
              : controller.updateMatchFilledBlank,
          onCompareSymbol: controller.updateComparePlacedSymbol,
        );

      default:
        return Text(
          'Unsupported question type: $type',
          style: const TextStyle(color: Colors.red),
        );
    }
  }
}

// ─── Submit button ────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size(180, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
        ),
      ),
      onPressed: onPressed,
      child: const Text(
        'Submit Answer',
        style: TextStyle(fontSize: 15),
      ),
    );
  }
}

// ─── Feedback banner ──────────────────────────────────────────────────────────

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({
    required this.isCorrect,
    required this.explanation,
    required this.screenWidth,
  });

  final bool isCorrect;
  final String explanation;
  final double screenWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCorrect ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCorrect ? Colors.green : Colors.red,
          width: 1.5,
        ),
      ),
      child: Text(
        isCorrect ? '✓ Correct! $explanation' : '✗ $explanation',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: screenWidth > 600 ? 15 : 13,
          fontWeight: FontWeight.w500,
          color: isCorrect ? Colors.green[800] : Colors.red[800],
        ),
      ),
    );
  }
}
