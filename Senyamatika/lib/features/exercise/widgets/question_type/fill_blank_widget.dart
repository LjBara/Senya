import 'package:flutter/material.dart';

/// Renders a fill-in-the-blank or write-number question.
///
/// The student types their answer in a text field and taps "Submit".
/// Local [TextEditingController] state is managed here; only the final
/// submitted answer is passed up via [onAnswer].
class FillBlankWidget extends StatefulWidget {
  const FillBlankWidget({
    super.key,
    required this.isAnswered,
    required this.userAnswer,
    required this.onAnswer,
    this.numericOnly = false,
  });

  final bool isAnswered;
  final dynamic userAnswer;
  final void Function(String answer) onAnswer;

  /// When [true] the keyboard is set to numeric (write_number type).
  final bool numericOnly;

  @override
  State<FillBlankWidget> createState() => _FillBlankWidgetState();
}

class _FillBlankWidgetState extends State<FillBlankWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return Column(
      children: [
        if (!widget.isAnswered) ...[
          SizedBox(
            width: sw * 0.5,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              keyboardType: widget.numericOnly
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                hintText: widget.numericOnly ? 'Type number' : 'Type answer',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.amber, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.amber, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              minimumSize: const Size(120, 44),
            ),
            onPressed: () {
              if (_controller.text.isNotEmpty) {
                widget.onAnswer(_controller.text);
              }
            },
            child: const Text(
              'Submit',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ] else if (widget.userAnswer != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Text(
              'Your answer: ${widget.userAnswer}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
