import 'package:flutter/foundation.dart';
import 'package:senyamatika_math_app/backend/services/ai_quiz_service.dart';

/// Callback used to persist a completed exercise score.
///
/// The call site (typically [ExerciseScreen]'s navigation call in main.dart)
/// owns the reference to [ProgressManager] and passes this closure so the
/// controller stays independent of that global.
typedef RecordScoreCallback = void Function(
  String lessonName,
  String language,
  int subLessonIndex,
  String exerciseTitle,
  int score,
  int totalQuestions,
  int correctAnswers,
  double percentage,
);

/// Drives a comprehensive lesson exercise from start to finish.
///
/// Responsibilities:
/// - Question navigation (next / previous / restart)
/// - Answer acceptance and correctness checking for all question types
/// - Intermediate drag-and-drop / matching state (preserved across prev/next)
/// - Score tracking and result recording via [RecordScoreCallback]
/// - Optional AI remediation ("Practice similar questions")
class ExerciseController extends ChangeNotifier {
  ExerciseController({
    required this.lessonName,
    required this.language,
    required this.exerciseTitle,
    required List<Map<String, dynamic>> questions,
    required RecordScoreCallback onRecordScore,
    List<String>? allLessonNames,
    this.showAiRemediation = false,
    this.autoStartRemediation = false,
    this.lessonId,
    this.aiLessonContext,
  })  : _questions = questions.map((q) => Map<String, dynamic>.from(q)).toList(),
        _onRecordScore = onRecordScore,
        _allLessonNames = allLessonNames {
    _userAnswers = List.filled(_questions.length, null);
    _answeredQuestions = List.filled(_questions.length, false);
    _initQuestion();
    if (autoStartRemediation && showAiRemediation) {
      // Schedule after the current sync frame so that listeners are attached
      // before the first notifyListeners() call from practiceSimilarQuestions.
      Future.microtask(practiceSimilarQuestions);
    }
  }

  final String lessonName;
  final String language;
  final String exerciseTitle;
  final bool showAiRemediation;

  /// When [true] and [showAiRemediation] is also true, AI question generation
  /// is triggered immediately on construction (before the user answers any
  /// questions). Used to redirect returning failed users to an AI quiz on
  /// re-entry without requiring them to complete the static quiz first.
  final bool autoStartRemediation;

  /// Lesson ID passed to the AI service for context resolution.
  final String? lessonId;

  /// Pre-built lesson context map for the AI service (built at the call site
  /// so this controller stays independent of [TopicsData]).
  final Map<String, dynamic>? aiLessonContext;

  final RecordScoreCallback _onRecordScore;

  /// When non-null, the score is recorded under every name in this list
  /// (used by the Fundamental Operations exercise which spans 4 lessons).
  final List<String>? _allLessonNames;

  // ─── Question state ───────────────────────────────────────────────────────

  List<Map<String, dynamic>> _questions;
  List<dynamic> _userAnswers = [];
  List<bool> _answeredQuestions = [];

  int _currentQuestion = 0;
  int _score = 0;
  bool _exerciseCompleted = false;
  bool _aiQuizLoading = false;

  // ─── Interactive (drag / match) state — keyed by question index ──────────

  /// Tap-select matching: { questionIndex → { leftIndex → rightIndex } }
  final Map<int, Map<int, int>> _matchingSelections = {};

  /// Filled blanks for drag_drop_order / drag_drop_symbols / drag_drop_match:
  ///   { questionIndex → { slotIndex → placedValue } }
  final Map<int, Map<int, String>> _matchFilledBlanks = {};

  /// Filled blanks for drag_drop (WN) / drag_drop_sequence:
  ///   { questionIndex → { blankPosition → placedValue } }
  final Map<int, Map<int, String>> _sequenceFilledBlanks = {};

  /// Single placed symbol for drag_drop_compare, per question.
  final Map<int, String?> _comparePlacedSymbols = {};

  /// Available (not-yet-placed) drag items for the current question.
  List<String> _dragItems = [];
  bool _dragItemsInitialized = false;

  // ─── Public read accessors ────────────────────────────────────────────────

  List<Map<String, dynamic>> get questions => List.unmodifiable(_questions);
  int get currentQuestion => _currentQuestion;
  int get score => _score;
  bool get exerciseCompleted => _exerciseCompleted;
  bool get aiQuizLoading => _aiQuizLoading;
  List<dynamic> get userAnswers => List.unmodifiable(_userAnswers);
  List<bool> get answeredQuestions => List.unmodifiable(_answeredQuestions);

  List<String> get dragItems => List.unmodifiable(_dragItems);
  bool get dragItemsInitialized => _dragItemsInitialized;
  Map<int, int> get currentMatchingSelections =>
      Map.unmodifiable(_matchingSelections[_currentQuestion] ?? {});
  Map<int, String> get currentMatchFilledBlanks =>
      Map.unmodifiable(_matchFilledBlanks[_currentQuestion] ?? {});
  Map<int, String> get currentSequenceFilledBlanks =>
      Map.unmodifiable(_sequenceFilledBlanks[_currentQuestion] ?? {});
  String? get currentComparePlacedSymbol =>
      _comparePlacedSymbols[_currentQuestion];

  // ─── Initialisation ───────────────────────────────────────────────────────

  void _initQuestion() {
    _dragItemsInitialized = false;
    _dragItems = [];

    final q = _questions[_currentQuestion];
    final type = q['type'] as String;

    switch (type) {
      case 'drag_drop':
        // WholeNumbers sequence-with-blanks type.
        _dragItems =
            List<String>.from(q['availableNumbers'] as List)..shuffle();
        _sequenceFilledBlanks[_currentQuestion] ??= {};
        break;
      case 'drag_drop_order':
        _dragItems = List<String>.from(q['items'] as List)..shuffle();
        _matchFilledBlanks[_currentQuestion] ??= {};
        break;
      case 'drag_drop_symbols':
        _dragItems = List<String>.from(q['symbols'] as List)..shuffle();
        _matchFilledBlanks[_currentQuestion] ??= {};
        break;
      case 'drag_drop_match':
        _dragItems = List<String>.from(q['rightItems'] as List)..shuffle();
        _matchFilledBlanks[_currentQuestion] ??= {};
        break;
      case 'drag_drop_sequence':
        _dragItems =
            List<String>.from(q['availableNumbers'] as List)..shuffle();
        _sequenceFilledBlanks[_currentQuestion] ??= {};
        break;
      case 'drag_drop_compare':
        _dragItems = List<String>.from(q['symbols'] as List)..shuffle();
        _comparePlacedSymbols[_currentQuestion] ??= null;
        break;
      case 'matching':
        _matchingSelections[_currentQuestion] ??= {};
        break;
    }

    _dragItemsInitialized = true;
  }

  // ─── Interactive state mutations (called by widgets) ─────────────────────

  void updateMatchingSelection(int leftIndex, int rightIndex) {
    _matchingSelections[_currentQuestion] ??= {};
    _matchingSelections[_currentQuestion]![leftIndex] = rightIndex;
    notifyListeners();
  }

  /// Place [value] at [slotIndex] for drag_drop_order / drag_drop_symbols / drag_drop_match.
  void updateMatchFilledBlank(int slotIndex, String value) {
    _matchFilledBlanks[_currentQuestion] ??= {};
    _matchFilledBlanks[_currentQuestion]![slotIndex] = value;
    _dragItems.remove(value);
    notifyListeners();
  }

  /// Place [value] at [position] for drag_drop (WN) or drag_drop_sequence.
  void updateSequenceBlank(int position, String value) {
    _sequenceFilledBlanks[_currentQuestion] ??= {};
    _sequenceFilledBlanks[_currentQuestion]![position] = value;
    _dragItems.remove(value);
    notifyListeners();
  }

  void updateComparePlacedSymbol(String symbol) {
    _comparePlacedSymbols[_currentQuestion] = symbol;
    _dragItems.remove(symbol);
    notifyListeners();
  }

  // ─── Completion checks ────────────────────────────────────────────────────

  bool isInteractiveComplete() {
    final q = _questions[_currentQuestion];
    final type = q['type'] as String;
    switch (type) {
      case 'matching':
        final m = _matchingSelections[_currentQuestion];
        return m != null && m.length == (q['leftItems'] as List).length;
      case 'drag_drop_order':
        final m = _matchFilledBlanks[_currentQuestion];
        return m != null && m.length == (q['items'] as List).length;
      case 'drag_drop_symbols':
        final m = _matchFilledBlanks[_currentQuestion];
        return m != null && m.length == (q['equations'] as List).length;
      case 'drag_drop_match':
        final m = _matchFilledBlanks[_currentQuestion];
        return m != null && m.length == (q['leftItems'] as List).length;
      case 'drag_drop':
      case 'drag_drop_sequence':
        final b = _sequenceFilledBlanks[_currentQuestion];
        return b != null &&
            b.length == (q['correctAnswer'] as List).length;
      case 'drag_drop_compare':
        return _comparePlacedSymbols[_currentQuestion] != null;
      default:
        return true;
    }
  }

  // ─── Answer submission ────────────────────────────────────────────────────

  /// Submit a direct answer (multiple_choice, fill_blank, true_false, etc.).
  void answerQuestion(dynamic answer) {
    if (_answeredQuestions[_currentQuestion]) return;
    final q = _questions[_currentQuestion];
    final isCorrect = _checkCorrectness(q, answer);
    _answeredQuestions[_currentQuestion] = true;
    _userAnswers[_currentQuestion] = answer;
    if (isCorrect) _score++;
    if (_answeredQuestions.every((a) => a)) {
      _exerciseCompleted = true;
      _recordResults();
    }
    notifyListeners();
  }

  /// Build the final answer from intermediate state and call [answerQuestion].
  /// Call this for interactive types (matching, drag_drop_*) when the student
  /// taps "Submit Answer".
  void submitInteractiveAnswer() {
    if (!isInteractiveComplete()) return;
    final q = _questions[_currentQuestion];
    final type = q['type'] as String;

    dynamic answer;
    switch (type) {
      case 'matching':
        answer = Map<int, int>.from(_matchingSelections[_currentQuestion]!);
        break;
      case 'drag_drop_order':
        final m = _matchFilledBlanks[_currentQuestion]!;
        answer = [
          for (int i = 0; i < (q['items'] as List).length; i++) m[i] ?? ''
        ];
        break;
      case 'drag_drop_symbols':
        final m = _matchFilledBlanks[_currentQuestion]!;
        answer = <int, String>{
          for (int i = 0; i < (q['equations'] as List).length; i++)
            i: m[i] ?? '',
        };
        break;
      case 'drag_drop_match':
        final m = _matchFilledBlanks[_currentQuestion]!;
        answer = [
          for (int i = 0; i < (q['leftItems'] as List).length; i++) m[i] ?? ''
        ];
        break;
      case 'drag_drop':
      case 'drag_drop_sequence':
        final b = _sequenceFilledBlanks[_currentQuestion]!;
        final bp = q['blankPositions'] as List;
        answer = [for (int i = 0; i < bp.length; i++) b[bp[i]] ?? ''];
        break;
      case 'drag_drop_compare':
        answer = _comparePlacedSymbols[_currentQuestion];
        break;
      default:
        return;
    }
    answerQuestion(answer);
  }

  // ─── Correctness ──────────────────────────────────────────────────────────

  bool _checkCorrectness(Map<String, dynamic> q, dynamic answer) {
    switch (q['type'] as String) {
      case 'multiple_choice':
      case 'circle_answer':
        return _mcIndex(answer) == _mcIndex(q['correctAnswer']);
      case 'fill_blank':
      case 'write_number':
        return answer.toString().trim() ==
            q['correctAnswer'].toString().trim();
      case 'true_false':
        return answer == q['correctAnswer'];
      case 'matching':
        return _checkMatching(answer as Map<int, int>, q['correctMatches']);
      case 'drag_drop':
      case 'drag_drop_sequence':
        return _checkListEquality(
            answer as List<String>, q['correctAnswer'] as List);
      case 'drag_drop_order':
        // drag_drop_order uses 'correctOrder', not 'correctAnswer'
        return _checkListEquality(
            answer as List<String>, q['correctOrder'] as List);
      case 'drag_drop_symbols':
        return _checkSymbols(
            answer as Map<int, String>, q['correctAnswer'] as List<dynamic>);
      case 'drag_drop_compare':
        return answer == q['correctSymbol'];
      case 'drag_drop_match':
        return _checkDDMatch(answer as List<String>,
            q['correctMatches'] as List, q['rightItems'] as List);
      default:
        return false;
    }
  }

  bool isAnswerCorrectAt(int index) {
    if (index < 0 || index >= _questions.length) return false;
    final answer = _userAnswers[index];
    if (answer == null) return false;
    return _checkCorrectness(_questions[index], answer);
  }

  // ─── Check helpers ────────────────────────────────────────────────────────

  int _mcIndex(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? -1;
    return -1;
  }

  bool _checkMatching(Map<int, int> user, List<dynamic> correct) {
    if (user.length != correct.length) return false;
    for (int i = 0; i < correct.length; i++) {
      if (user[i] != correct[i]) return false;
    }
    return true;
  }

  bool _checkListEquality(List<String> user, List<dynamic> correct) {
    if (user.length != correct.length) return false;
    for (int i = 0; i < correct.length; i++) {
      if (user[i] != correct[i].toString()) return false;
    }
    return true;
  }

  bool _checkSymbols(Map<int, String> placed, List<dynamic> correctAnswer) {
    if (placed.length != correctAnswer.length) return false;
    for (int i = 0; i < correctAnswer.length; i++) {
      if (placed[i] != correctAnswer[i].toString()) return false;
    }
    return true;
  }

  bool _checkDDMatch(
      List<String> userMatches, List<dynamic> correctMatches, List<dynamic> rightItems) {
    if (userMatches.length != correctMatches.length) return false;
    for (int i = 0; i < correctMatches.length; i++) {
      final expected = rightItems[correctMatches[i] as int].toString();
      if (userMatches[i] != expected) return false;
    }
    return true;
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void nextQuestion() {
    if (_currentQuestion < _questions.length - 1) {
      _currentQuestion++;
      _initQuestion();
      notifyListeners();
    }
  }

  void previousQuestion() {
    if (_currentQuestion > 0) {
      _currentQuestion--;
      _initQuestion();
      notifyListeners();
    }
  }

  void restartExercise() {
    _currentQuestion = 0;
    _score = 0;
    _exerciseCompleted = false;
    _questions = _questions.map((q) => Map<String, dynamic>.from(q)).toList();
    _userAnswers = List.filled(_questions.length, null);
    _answeredQuestions = List.filled(_questions.length, false);
    _matchingSelections.clear();
    _matchFilledBlanks.clear();
    _sequenceFilledBlanks.clear();
    _comparePlacedSymbols.clear();
    _initQuestion();
    notifyListeners();
  }

  /// Called by the "Try Again" button on the results screen.
  ///
  /// When AI remediation is enabled and the user failed (< 70%), generates a
  /// fresh AI question set for the wrong answers. Otherwise falls back to a
  /// plain restart with the current question list.
  Future<void> retryWithRemediation() async {
    final pct = _questions.isEmpty ? 0.0 : (_score / _questions.length * 100);
    if (showAiRemediation && pct < 70.0) {
      await practiceSimilarQuestions();
    } else {
      restartExercise();
    }
  }

  /// Called by the "Finish" button on the last question.
  ///
  /// By the time the button is enabled ([exerciseCompleted] is already true),
  /// this simply triggers a Consumer re-evaluation so the results screen is
  /// shown. Acts as a reliable manual fallback for cases where the automatic
  /// transition has not fired yet.
  void finishExercise() {
    if (_exerciseCompleted) notifyListeners();
  }

  // ─── Results recording ────────────────────────────────────────────────────

  void _recordResults() {
    final pct = (_score / _questions.length * 100).toDouble();
    final lessons = _allLessonNames ?? [lessonName];
    for (final name in lessons) {
      _onRecordScore(name, language, 0, exerciseTitle, _score,
          _questions.length, _score, pct);
    }
  }

  // ─── AI remediation ───────────────────────────────────────────────────────

  List<int> incorrectIndices() {
    return [
      for (int i = 0; i < _questions.length; i++)
        if (!isAnswerCorrectAt(i)) i
    ];
  }

  List<Map<String, dynamic>> get incorrectQuestions =>
      incorrectIndices().map((i) => Map<String, dynamic>.from(_questions[i])).toList();

  Future<void> practiceSimilarQuestions() async {
    final incorrect = incorrectQuestions;
    if (incorrect.isEmpty) return;

    final effectiveLessonId = lessonId ?? lessonName;
    final effectiveContext = aiLessonContext ?? {'lessonTitle': lessonName};
    final slots = AiQuizService.buildRemediationSlots(incorrect);

    _aiQuizLoading = true;
    _aiError = null;
    notifyListeners();

    try {
      final result = await AiQuizService.generateRemediationQuestions(
        lessonId: effectiveLessonId,
        lessonContext: effectiveContext,
        remediationSlots: slots,
        originalIncorrectQuestions: incorrect,
      );

      final raw = result['questions'];
      final generated = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) generated.add(Map<String, dynamic>.from(e));
        }
      }

      if (generated.isEmpty) {
        _aiError = result['error']?.toString() ??
            'Could not generate practice questions. Please try again.';
        return;
      }

      final wrongIndices = incorrectIndices();
      // When the API returns a full replacement set (one generated question per
      // quiz slot), use it entirely so retakes show a fresh quiz instead of
      // mixing unchanged static questions for slots the learner got right.
      final List<Map<String, dynamic>> merged;
      if (generated.length >= _questions.length) {
        merged = [
          for (int i = 0; i < _questions.length; i++)
            Map<String, dynamic>.from(generated[i]),
        ];
      } else {
        merged = _mergeWithGenerated(generated, wrongIndices);
      }
      _questions = merged;
      _currentQuestion = wrongIndices.isEmpty
          ? 0
          : wrongIndices.first.clamp(0, merged.length - 1);
      _score = 0;
      _exerciseCompleted = false;
      _userAnswers = List.filled(_questions.length, null);
      _answeredQuestions = List.filled(_questions.length, false);
      _matchingSelections.clear();
      _matchFilledBlanks.clear();
      _sequenceFilledBlanks.clear();
      _comparePlacedSymbols.clear();
      _initQuestion();
    } catch (e) {
      _aiError = 'An error occurred while generating questions. Please try again.';
    } finally {
      _aiQuizLoading = false;
      notifyListeners();
    }
  }

  String? get aiError => _aiError;
  String? _aiError;

  /// Partial merge: keeps static questions for slots the learner answered
  /// correctly and inserts [gen] for incorrect slots. Used only when the API
  /// returns fewer items than the current quiz length.
  List<Map<String, dynamic>> _mergeWithGenerated(
      List<Map<String, dynamic>> gen, List<int> wrongIndices) {
    final merged = <Map<String, dynamic>>[];
    var genI = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (isAnswerCorrectAt(i)) {
        merged.add(Map<String, dynamic>.from(_questions[i]));
      } else {
        if (genI < gen.length) {
          merged.add(Map<String, dynamic>.from(gen[genI]));
          genI++;
        } else {
          merged.add(Map<String, dynamic>.from(_questions[i]));
        }
      }
    }
    while (genI < gen.length) {
      merged.add(Map<String, dynamic>.from(gen[genI]));
      genI++;
    }
    return merged;
  }
}
