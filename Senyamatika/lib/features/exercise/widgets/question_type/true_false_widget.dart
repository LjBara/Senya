import 'package:flutter/material.dart';

/// Renders a true/false question with two large tappable buttons.
class TrueFalseWidget extends StatelessWidget {
  const TrueFalseWidget({
    super.key,
    required this.isAnswered,
    required this.userAnswer,
    required this.correctAnswer,
    required this.onAnswer,
  });

  final bool isAnswered;
  final dynamic userAnswer;
  final bool correctAnswer;
  final void Function(bool answer) onAnswer;

  Color _colorFor(bool value) {
    if (!isAnswered) return Colors.white;
    final selected = userAnswer == value;
    final correct = value == correctAnswer;
    if (selected && correct) return Colors.green;
    if (selected && !correct) return Colors.red;
    if (!selected && correct) return Colors.green[100]!;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TrueFalseButton(
            label: 'TRUE',
            icon: Icons.check_circle_outline,
            color: _colorFor(true),
            onTap: isAnswered ? null : () => onAnswer(true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TrueFalseButton(
            label: 'FALSE',
            icon: Icons.cancel_outlined,
            color: _colorFor(false),
            onTap: isAnswered ? null : () => onAnswer(false),
          ),
        ),
      ],
    );
  }
}

class _TrueFalseButton extends StatelessWidget {
  const _TrueFalseButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 80,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[400]!, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
