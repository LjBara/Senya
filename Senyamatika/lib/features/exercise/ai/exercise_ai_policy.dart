/// Pure policy helpers for AI remediation wiring.
///
/// These functions contain no imports from main.dart, ProgressManager, or
/// TopicsData — they operate on primitive values so they remain testable and
/// reusable from any call site.
library exercise_ai_policy;

/// Returns [true] when the user should be auto-redirected to an AI quiz on
/// exercise entry: they have attempted before but have never passed.
bool shouldAutoStartRemediation({
  required bool hasAnyAttempt,
  required bool hasAnyPass,
}) =>
    hasAnyAttempt && !hasAnyPass;

/// Aggregates attempt / pass flags across one or more progress lesson names.
///
/// [lessonNames] is the list of lesson names to check (a single item for most
/// exercises; four items for Fundamental Operations).
///
/// [completedCount] returns how many recorded exercise entries exist for a
/// given lesson name — typically `ProgressManager.getCompletedExercisesForLesson`.
///
/// [hasPassed] returns whether any recorded entry for a lesson name has a
/// passing score — typically `ProgressManager.hasEverPassedExercise`.
///
/// Returns `(hasAnyAttempt, hasAnyPass)`.
({bool hasAnyAttempt, bool hasAnyPass}) aggregateProgressFlags(
  List<String> lessonNames, {
  required int Function(String lessonName) completedCount,
  required bool Function(String lessonName) hasPassed,
}) {
  final hasAnyAttempt = lessonNames.any((n) => completedCount(n) > 0);
  final hasAnyPass = lessonNames.any((n) => hasPassed(n));
  return (hasAnyAttempt: hasAnyAttempt, hasAnyPass: hasAnyPass);
}

/// Builds the AI lesson context map sent to `POST /ai/generate-questions`.
///
/// Only non-null / non-empty fields are included so the backend strict schema
/// does not reject extra keys with null values.
///
/// [lessonId]     canonical lesson id (e.g. `lesson1_2`).
/// [lessonTitle]  human-readable lesson title (e.g. `'Comparison'`).
/// [subtopics]    curriculum subtopic titles merged into prompt context.
/// [topicId]      optional topic id (e.g. `topic1`).
/// [topicTitle]   optional topic title (e.g. `'1. Number Values'`).
Map<String, dynamic> buildAiLessonContext({
  required String lessonTitle,
  List<String> subtopics = const [],
  String? topicId,
  String? topicTitle,
}) {
  return {
    'lessonTitle': lessonTitle,
    if (subtopics.isNotEmpty) 'subtopics': subtopics,
    if (topicId != null && topicId.isNotEmpty) 'topicId': topicId,
    if (topicTitle != null && topicTitle.isNotEmpty) 'topicTitle': topicTitle,
  };
}
