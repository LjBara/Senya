import 'package:flutter/material.dart';

/// Renders a multiple-choice or circle-answer question.
///
/// Both types share the same data shape and visual layout — a 2-column grid
/// of tappable option tiles that highlight correct/incorrect once answered.
class McQuestionWidget extends StatelessWidget {
  const McQuestionWidget({
    super.key,
    required this.question,
    required this.isAnswered,
    required this.userAnswer,
    required this.onAnswer,
    this.circleStyle = false,
  });

  final Map<String, dynamic> question;
  final bool isAnswered;
  final dynamic userAnswer;
  final void Function(int optionIndex) onAnswer;

  /// When [true] the tiles use a circular/pill shape (circle_answer style).
  final bool circleStyle;

  int _correctIndex() {
    final v = question['correctAnswer'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? -1;
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final options = question['options'] as List;
    final sw = MediaQuery.of(context).size.width;
    final correct = _correctIndex();
    final objectsRaw = question['objects'];
    final objects = objectsRaw is List ? objectsRaw : const <dynamic>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (objects.isNotEmpty) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final o in objects)
                Text(
                  o.toString(),
                  style: TextStyle(
                    fontSize: sw > 600 ? 28 : 24,
                    height: 1.1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: sw > 600 ? 2.2 : 2.0,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: options.length,
          itemBuilder: (context, i) {
            final isSelected = isAnswered && userAnswer == i;
            final isCorrect = i == correct;

            Color tileColor = Colors.white;
            if (isAnswered) {
              if (isSelected && isCorrect) {
                tileColor = Colors.green;
              } else if (isSelected) {
                tileColor = Colors.red;
              } else if (isCorrect) {
                tileColor = Colors.green[100]!;
              }
            }

            final borderRadius = circleStyle
                ? BorderRadius.circular(30)
                : BorderRadius.circular(10);

            return GestureDetector(
              onTap: isAnswered ? null : () => onAnswer(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      options[i].toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: sw > 600 ? 18 : 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
