import 'package:flutter/material.dart';

/// Unified drag-and-drop question widget.
///
/// Dispatches to the correct sub-layout based on [question]'s `type` field:
/// - `drag_drop`          — fill blanks in a number sequence (Whole Numbers)
/// - `drag_drop_order`    — reorder items into a target sequence
/// - `drag_drop_symbols`  — place comparison symbols into equation slots
/// - `drag_drop_sequence` — fill blanks across labelled equations
/// - `drag_drop_compare`  — place one comparison symbol between two groups
/// - `drag_drop_match`    — drag right-items to match each left-item
///
/// Intermediate state ([dragItems], [filledBlanks], [comparePlacedSymbol])
/// is owned by [ExerciseController] and passed as parameters so state is
/// preserved when navigating previous/next. Mutation callbacks route back to
/// the controller.
class DragDropWidget extends StatelessWidget {
  const DragDropWidget({
    super.key,
    required this.question,
    required this.dragItems,
    required this.filledBlanks,
    required this.comparePlacedSymbol,
    required this.isAnswered,
    required this.onFillBlank,
    required this.onCompareSymbol,
  });

  final Map<String, dynamic> question;

  /// Available (not-yet-placed) draggable items.
  final List<String> dragItems;

  /// { slotIndex → placedValue } used by order / symbols / match / sequence.
  final Map<int, String> filledBlanks;

  /// Placed symbol for drag_drop_compare.
  final String? comparePlacedSymbol;

  final bool isAnswered;

  /// Called when any slot receives a dragged item.
  /// [slotKey] is the slot index; [value] is the dragged string.
  final void Function(int slotKey, String value) onFillBlank;

  /// Called when the compare-type symbol target receives a value.
  final void Function(String symbol) onCompareSymbol;

  @override
  Widget build(BuildContext context) {
    final type = question['type'] as String;
    switch (type) {
      case 'drag_drop':
        return _DragDropSequence(
          question: question,
          dragItems: dragItems,
          filledBlanks: filledBlanks,
          isAnswered: isAnswered,
          onFill: onFillBlank,
          usePositionKeys: true,
        );
      case 'drag_drop_sequence':
        return _DragDropSequence(
          question: question,
          dragItems: dragItems,
          filledBlanks: filledBlanks,
          isAnswered: isAnswered,
          onFill: onFillBlank,
          usePositionKeys: true,
        );
      case 'drag_drop_order':
        return _DragDropOrder(
          question: question,
          dragItems: dragItems,
          filledBlanks: filledBlanks,
          isAnswered: isAnswered,
          onFill: onFillBlank,
        );
      case 'drag_drop_symbols':
        return _DragDropSymbols(
          question: question,
          dragItems: dragItems,
          filledBlanks: filledBlanks,
          isAnswered: isAnswered,
          onFill: onFillBlank,
        );
      case 'drag_drop_compare':
        return _DragDropCompare(
          question: question,
          dragItems: dragItems,
          placedSymbol: comparePlacedSymbol,
          isAnswered: isAnswered,
          onPlace: onCompareSymbol,
        );
      case 'drag_drop_match':
        return _DragDropMatch(
          question: question,
          dragItems: dragItems,
          filledBlanks: filledBlanks,
          isAnswered: isAnswered,
          onFill: onFillBlank,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─── Draggable chip ──────────────────────────────────────────────────────────

class _DraggableChip extends StatelessWidget {
  const _DraggableChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: label,
      feedback: Material(
        color: Colors.transparent,
        child: _Chip(label: label, color: Colors.deepPurple),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _Chip(label: label, color: Colors.grey),
      ),
      child: _Chip(label: label, color: Colors.deepPurple),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─── Drop target ─────────────────────────────────────────────────────────────

class _DropSlot extends StatelessWidget {
  const _DropSlot({
    required this.slotIndex,
    required this.filledValue,
    required this.isAnswered,
    required this.onAccept,
    this.width = 60,
  });

  final int slotIndex;
  final String? filledValue;
  final bool isAnswered;
  final void Function(int index, String value) onAccept;
  final double width;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      builder: (ctx, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          height: 40,
          decoration: BoxDecoration(
            color: filledValue == null
                ? (hovering ? Colors.purple[50] : Colors.grey[100])
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hovering
                  ? Colors.purple
                  : (filledValue != null ? Colors.deepPurple : Colors.grey[400]!),
              width: hovering ? 2 : 1.5,
            ),
          ),
          child: Center(
            child: Text(
              filledValue ?? '__',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color:
                    filledValue == null ? Colors.grey[400] : Colors.deepPurple,
              ),
            ),
          ),
        );
      },
      onWillAccept: (_) => !isAnswered && filledValue == null,
      onAccept: (value) => onAccept(slotIndex, value),
    );
  }
}

// ─── Drag bank (shared) ──────────────────────────────────────────────────────

class _DragBank extends StatelessWidget {
  const _DragBank({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple[200]!, width: 1.5),
      ),
      child: Column(
        children: [
          const Text(
            'Drag items:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: items.map((item) => _DraggableChip(label: item)).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── drag_drop / drag_drop_sequence ─────────────────────────────────────────

class _DragDropSequence extends StatelessWidget {
  const _DragDropSequence({
    required this.question,
    required this.dragItems,
    required this.filledBlanks,
    required this.isAnswered,
    required this.onFill,
    required this.usePositionKeys,
  });

  final Map<String, dynamic> question;
  final List<String> dragItems;
  final Map<int, String> filledBlanks;
  final bool isAnswered;
  final void Function(int position, String value) onFill;
  final bool usePositionKeys;

  @override
  Widget build(BuildContext context) {
    final sequence = question['sequence'] as List;
    final blankPositions = question['blankPositions'] as List;

    return Column(
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: List.generate(sequence.length, (i) {
            final isBlank = blankPositions.contains(i);
            if (!isBlank) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[300]!),
                ),
                child: Text(
                  sequence[i].toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }
            return _DropSlot(
              slotIndex: i,
              filledValue: filledBlanks[i],
              isAnswered: isAnswered,
              onAccept: onFill,
              width: 70,
            );
          }),
        ),
        const SizedBox(height: 12),
        _DragBank(items: dragItems),
      ],
    );
  }
}

// ─── drag_drop_order ─────────────────────────────────────────────────────────

class _DragDropOrder extends StatelessWidget {
  const _DragDropOrder({
    required this.question,
    required this.dragItems,
    required this.filledBlanks,
    required this.isAnswered,
    required this.onFill,
  });

  final Map<String, dynamic> question;
  final List<String> dragItems;
  final Map<int, String> filledBlanks;
  final bool isAnswered;
  final void Function(int slotIndex, String value) onFill;

  @override
  Widget build(BuildContext context) {
    final items = question['items'] as List;

    return Column(
      children: [
        const Text(
          'Drop items in the correct order:',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: List.generate(
            items.length,
            (i) => _DropSlot(
              slotIndex: i,
              filledValue: filledBlanks[i],
              isAnswered: isAnswered,
              onAccept: onFill,
              width: 64,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _DragBank(items: dragItems),
      ],
    );
  }
}

// ─── drag_drop_symbols ───────────────────────────────────────────────────────

class _DragDropSymbols extends StatelessWidget {
  const _DragDropSymbols({
    required this.question,
    required this.dragItems,
    required this.filledBlanks,
    required this.isAnswered,
    required this.onFill,
  });

  final Map<String, dynamic> question;
  final List<String> dragItems;
  final Map<int, String> filledBlanks;
  final bool isAnswered;
  final void Function(int equationIndex, String symbol) onFill;

  @override
  Widget build(BuildContext context) {
    final equations = question['equations'] as List;

    return Column(
      children: [
        ...List.generate(equations.length, (i) {
          final eq = equations[i] as Map;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _NumberBox(label: eq['left'].toString()),
                const SizedBox(width: 8),
                _DropSlot(
                  slotIndex: i,
                  filledValue: filledBlanks[i],
                  isAnswered: isAnswered,
                  onAccept: onFill,
                  width: 50,
                ),
                const SizedBox(width: 8),
                _NumberBox(label: eq['right'].toString()),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
        _DragBank(items: dragItems),
      ],
    );
  }
}

class _NumberBox extends StatelessWidget {
  const _NumberBox({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[300]!),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ─── drag_drop_compare ───────────────────────────────────────────────────────

class _DragDropCompare extends StatelessWidget {
  const _DragDropCompare({
    required this.question,
    required this.dragItems,
    required this.placedSymbol,
    required this.isAnswered,
    required this.onPlace,
  });

  final Map<String, dynamic> question;
  final List<String> dragItems;
  final String? placedSymbol;
  final bool isAnswered;
  final void Function(String symbol) onPlace;

  @override
  Widget build(BuildContext context) {
    final leftGroup = question['leftGroup'] as List;
    final rightGroup = question['rightGroup'] as List;
    final leftCount = question['leftCount'] as int;
    final rightCount = question['rightCount'] as int;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GroupBox(label: leftGroup.join(' '), count: leftCount),
            const SizedBox(width: 12),
            DragTarget<String>(
              builder: (ctx, candidates, _) {
                final hovering = candidates.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: placedSymbol == null
                        ? (hovering ? Colors.orange[50] : Colors.grey[100])
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hovering
                          ? Colors.orange
                          : (placedSymbol != null
                              ? Colors.deepOrange
                              : Colors.grey[400]!),
                      width: hovering ? 2.5 : 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      placedSymbol ?? '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: placedSymbol == null
                            ? Colors.grey[400]
                            : Colors.deepOrange,
                      ),
                    ),
                  ),
                );
              },
              onWillAccept: (_) => !isAnswered && placedSymbol == null,
              onAccept: (s) => onPlace(s),
            ),
            const SizedBox(width: 12),
            _GroupBox(label: rightGroup.join(' '), count: rightCount),
          ],
        ),
        const SizedBox(height: 16),
        _DragBank(items: dragItems),
      ],
    );
  }
}

class _GroupBox extends StatelessWidget {
  const _GroupBox({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        const SizedBox(height: 4),
        Text(
          'Count: $count',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
      ],
    );
  }
}

// ─── drag_drop_match ─────────────────────────────────────────────────────────

class _DragDropMatch extends StatelessWidget {
  const _DragDropMatch({
    required this.question,
    required this.dragItems,
    required this.filledBlanks,
    required this.isAnswered,
    required this.onFill,
  });

  final Map<String, dynamic> question;
  final List<String> dragItems;
  final Map<int, String> filledBlanks;
  final bool isAnswered;
  final void Function(int leftIndex, String value) onFill;

  @override
  Widget build(BuildContext context) {
    final leftItems = question['leftItems'] as List;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange, width: 1.5),
          ),
          child: Column(
            children: List.generate(leftItems.length, (i) {
              final placedValue = filledBlanks[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange[300]!),
                        ),
                        child: Text(
                          leftItems[i].toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DragTarget<String>(
                        builder: (ctx, candidates, _) {
                          final hovering = candidates.isNotEmpty;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: 40,
                            decoration: BoxDecoration(
                              color: placedValue == null
                                  ? (hovering
                                      ? Colors.orange[100]
                                      : Colors.orange[50])
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: hovering
                                    ? Colors.orange
                                    : (placedValue != null
                                        ? Colors.orange[700]!
                                        : Colors.orange[300]!),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                placedValue ?? 'Drop',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: placedValue == null
                                      ? Colors.grey
                                      : Colors.black,
                                ),
                              ),
                            ),
                          );
                        },
                        onWillAccept: (_) =>
                            !isAnswered && filledBlanks[i] == null,
                        onAccept: (value) => onFill(i, value),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        _DragBank(items: dragItems),
      ],
    );
  }
}
