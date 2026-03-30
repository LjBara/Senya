import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senyamatika_math_app/features/exercise/controller/exercise_controller.dart';

/// Results screen shown when all questions in the exercise have been answered.
///
/// Always shows: score card, Try Again, Back to Lessons.
///
/// When the controller has [ExerciseController.showAiRemediation] set to true
/// and the score is below the 70% pass threshold, "Try Again" automatically
/// generates a fresh AI question set via [ExerciseController.retryWithRemediation].
/// For all other cases "Try Again" performs a plain restart.
class ExerciseResultsScreen extends StatelessWidget {
  const ExerciseResultsScreen({
    super.key,
    required this.exerciseTitle,
    this.onAiError,
  });

  final String exerciseTitle;

  /// Called when the AI generation request triggered by "Try Again" fails,
  /// so the parent [ExerciseScreen] can surface a [SnackBar].
  final void Function(String message)? onAiError;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExerciseController>();
    final total = controller.questions.length;
    final score = controller.score;
    final percentage = total > 0 ? (score / total * 100).round() : 0;
    final sw = MediaQuery.of(context).size.width;

    final (message, emoji, color) = switch (percentage) {
      100 => ('Perfect Score!', '🏆', Colors.amber),
      >= 80 => ('Great Job!', '🎉', Colors.green),
      >= 60 => ('Good Try!', '👍', Colors.blue),
      _ => ('Keep Practicing!', '💪', Colors.orange),
    };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Exercise Complete'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 80)),
              const SizedBox(height: 20),
              Text(
                message,
                style: TextStyle(
                  fontSize: sw > 600 ? 32 : 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 30),

              // Score card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color, width: 3),
                ),
                child: Column(
                  children: [
                    const Text('Your Score', style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 10),
                    Text(
                      '$score/$total',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$percentage%',
                      style: const TextStyle(fontSize: 28),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Action row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black,
                        side: const BorderSide(color: Colors.black, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: controller.aiQuizLoading
                          ? null
                          : () => _onTryAgain(context, controller),
                      child: controller.aiQuizLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Try Again',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF59D),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: const BorderSide(
                              color: Colors.black, width: 1.5),
                        ),
                      ),
                      onPressed: controller.aiQuizLoading
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text(
                        'Back to Lessons',
                        style: TextStyle(fontSize: 16),
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
  }

  Future<void> _onTryAgain(
    BuildContext context,
    ExerciseController controller,
  ) async {
    await controller.retryWithRemediation();

    if (!context.mounted) return;

    if (controller.aiError != null) {
      onAiError?.call(controller.aiError!);
    }
  }
}
