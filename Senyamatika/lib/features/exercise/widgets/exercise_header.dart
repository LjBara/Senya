import 'package:flutter/material.dart';

/// Question counter + type label + score chip row displayed above each question.
class ExerciseHeader extends StatelessWidget {
  const ExerciseHeader({
    super.key,
    required this.currentQuestion,
    required this.totalQuestions,
    required this.questionType,
    required this.score,
  });

  final int currentQuestion;
  final int totalQuestions;
  final String questionType;
  final int score;

  static Color typeColor(String type) {
    switch (type) {
      case 'multiple_choice':
        return Colors.blue;
      case 'circle_answer':
        return Colors.teal;
      case 'fill_blank':
        return Colors.green;
      case 'write_number':
        return Colors.amber;
      case 'matching':
        return Colors.purple;
      case 'true_false':
        return Colors.red;
      default:
        // All drag_drop variants
        return Colors.orange;
    }
  }

  static String typeName(String type) {
    switch (type) {
      case 'multiple_choice':
        return 'MULTIPLE CHOICE';
      case 'circle_answer':
        return 'CIRCLE THE ANSWER';
      case 'fill_blank':
        return 'FILL IN THE BLANK';
      case 'write_number':
        return 'WRITE THE NUMBER';
      case 'matching':
        return 'MATCHING TYPE';
      case 'true_false':
        return 'TRUE OR FALSE';
      case 'drag_drop':
        return 'DRAG & DROP';
      case 'drag_drop_order':
        return 'DRAG & DROP – ORDER';
      case 'drag_drop_symbols':
        return 'DRAG & DROP – SYMBOLS';
      case 'drag_drop_sequence':
        return 'DRAG & DROP – SEQUENCE';
      case 'drag_drop_compare':
        return 'DRAG & DROP – COMPARE';
      case 'drag_drop_match':
        return 'DRAG & DROP – MATCH';
      default:
        return type.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final color = typeColor(questionType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Question ${currentQuestion + 1}/$totalQuestions',
                style: TextStyle(
                  fontSize: sw * 0.04,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                typeName(questionType),
                style: TextStyle(
                  fontSize: sw * 0.032,
                  color: color.withOpacity(0.8),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: sw * 0.04,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
