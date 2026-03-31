import 'package:flutter/material.dart';

/// Renders a tap-select matching question.
///
/// Each left item gets a [DropdownButton] to pick from the right items.
/// Intermediate selection state is owned by [ExerciseController] and passed
/// in via [selections]. Changes are surfaced via [onSelectionChanged].
class MatchingWidget extends StatelessWidget {
  const MatchingWidget({
    super.key,
    required this.question,
    required this.isAnswered,
    required this.selections,
    required this.onSelectionChanged,
  });

  final Map<String, dynamic> question;
  final bool isAnswered;

  /// { leftIndex → selectedRightIndex }
  final Map<int, int> selections;
  final void Function(int leftIndex, int rightIndex) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final left = question['leftItems'] as List;
    final right = question['rightItems'] as List;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple[200]!, width: 1.5),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          ...List.generate(
            left.length,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MatchRow(
                leftLabel: left[i].toString(),
                rightItems: right,
                selectedRightIndex: selections[i],
                isAnswered: isAnswered,
                onChanged: (v) => onSelectionChanged(i, v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.purple[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Item',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.purple[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Match',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.leftLabel,
    required this.rightItems,
    required this.selectedRightIndex,
    required this.isAnswered,
    required this.onChanged,
  });

  final String leftLabel;
  final List rightItems;
  final int? selectedRightIndex;
  final bool isAnswered;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              leftLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.purple[300]!),
            ),
            child: DropdownButton<int>(
              value: selectedRightIndex,
              hint: const Text('Select', style: TextStyle(fontSize: 12)),
              isExpanded: true,
              underline: const SizedBox(),
              iconSize: 20,
              items: List.generate(
                rightItems.length,
                (j) => DropdownMenuItem<int>(
                  value: j,
                  child: Text(
                    rightItems[j].toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              onChanged: isAnswered ? null : (v) => onChanged(v!),
            ),
          ),
        ),
      ],
    );
  }
}
