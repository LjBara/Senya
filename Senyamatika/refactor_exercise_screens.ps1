param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$file = "C:\Users\Drew\Desktop\Projects\senyamatika-1\Senya\Senyamatika\lib\main.dart"
$lines = [System.IO.File]::ReadAllLines($file)
$out   = [System.Collections.Generic.List[string]]::new()

# ─── Thin wrapper definitions ─────────────────────────────────────────────────

$wn = @(
  '/// Thin wrapper — exercise logic lives in the [exercise_feature.ExerciseScreen] module.',
  'class WholeNumbersExerciseScreen extends StatelessWidget {',
  '  final String lessonName;',
  '  final String language;',
  '  const WholeNumbersExerciseScreen(',
  '      {super.key, required this.lessonName, required this.language});',
  '  @override',
  "  Widget build(BuildContext context) => exercise_feature.ExerciseScreen(",
  '    lessonName: lessonName,',
  '    language: language,',
  "    title: 'Whole Numbers Exercise',",
  '    questions: WholeNumbersQuestions.all,',
  '    showAiRemediation: true,',
  '    onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>',
  '        progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),',
  '    lessonId: lessonName,',
  '  );',
  '}',
  ''
)

$cmp = @(
  '/// Thin wrapper — exercise logic lives in the [exercise_feature.ExerciseScreen] module.',
  'class ComparisonComprehensiveExerciseScreen extends StatelessWidget {',
  '  final String lessonName;',
  '  final String language;',
  '  const ComparisonComprehensiveExerciseScreen(',
  '      {super.key, required this.lessonName, required this.language});',
  '  @override',
  "  Widget build(BuildContext context) => exercise_feature.ExerciseScreen(",
  '    lessonName: lessonName,',
  '    language: language,',
  "    title: 'Comparison Exercise',",
  '    questions: ComparisonQuestions.all,',
  '    onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>',
  '        progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),',
  '  );',
  '}',
  ''
)

$fo = @(
  '/// Thin wrapper — exercise logic lives in the [exercise_feature.ExerciseScreen] module.',
  'class FundamentalOperationsExerciseScreen extends StatelessWidget {',
  '  final String lessonName;',
  '  final String language;',
  '  const FundamentalOperationsExerciseScreen(',
  '      {super.key, required this.lessonName, required this.language});',
  '  @override',
  "  Widget build(BuildContext context) => exercise_feature.ExerciseScreen(",
  '    lessonName: lessonName,',
  '    language: language,',
  "    title: 'Fundamental Operations Exercise',",
  '    questions: FundamentalOperationsQuestions.all,',
  '    allLessonNames: FundamentalOperationsQuestions.allLessonNames,',
  '    onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>',
  '        progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),',
  '  );',
  '}',
  ''
)

$fr = @(
  '/// Thin wrapper — exercise logic lives in the [exercise_feature.ExerciseScreen] module.',
  'class FractionExerciseScreen extends StatelessWidget {',
  '  final String lessonName;',
  '  final String language;',
  '  const FractionExerciseScreen(',
  '      {super.key, required this.lessonName, required this.language});',
  '  @override',
  "  Widget build(BuildContext context) => exercise_feature.ExerciseScreen(",
  '    lessonName: lessonName,',
  '    language: language,',
  "    title: 'Fraction Exercise',",
  '    questions: FractionsQuestions.all,',
  '    onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>',
  '        progressManager.recordExerciseScore(lesson, lang, idx, type, s, t, c, pct),',
  '  );',
  '}',
  ''
)

$dec = @(
  '/// Thin wrapper — exercise logic lives in the [exercise_feature.ExerciseScreen] module.',
  'class DecimalExerciseScreen extends StatelessWidget {',
  '  final String lessonName;',
  '  final String language;',
  '  final int subLessonIndex;',
  '  const DecimalExerciseScreen(',
  '      {super.key, required this.lessonName, required this.language, required this.subLessonIndex});',
  '  @override',
  "  Widget build(BuildContext context) => exercise_feature.ExerciseScreen(",
  '    lessonName: lessonName,',
  '    language: language,',
  "    title: 'Decimal Numbers Exercise',",
  '    questions: DecimalsQuestions.all,',
  '    onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>',
  '        progressManager.recordExerciseScore(lesson, lang, subLessonIndex, type, s, t, c, pct),',
  '  );',
  '}',
  ''
)

$pct = @(
  '/// Thin wrapper — exercise logic lives in the [exercise_feature.ExerciseScreen] module.',
  'class PercentageExerciseScreen extends StatelessWidget {',
  '  final String lessonName;',
  '  final String language;',
  '  final int subLessonIndex;',
  '  const PercentageExerciseScreen(',
  '      {super.key, required this.lessonName, required this.language, required this.subLessonIndex});',
  '  @override',
  "  Widget build(BuildContext context) => exercise_feature.ExerciseScreen(",
  '    lessonName: lessonName,',
  '    language: language,',
  "    title: 'Percentage Exercise',",
  '    questions: PercentagesQuestions.all,',
  '    onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>',
  '        progressManager.recordExerciseScore(lesson, lang, subLessonIndex, type, s, t, c, pct),',
  '  );',
  '}',
  ''
)

$alg = @(
  '/// Thin wrapper — exercise logic lives in the [exercise_feature.ExerciseScreen] module.',
  'class AlgebraExerciseScreen extends StatelessWidget {',
  '  final String lessonName;',
  '  final String language;',
  '  final int subLessonIndex;',
  '  const AlgebraExerciseScreen(',
  '      {super.key, required this.lessonName, required this.language, required this.subLessonIndex});',
  '  @override',
  "  Widget build(BuildContext context) => exercise_feature.ExerciseScreen(",
  '    lessonName: lessonName,',
  '    language: language,',
  "    title: 'Algebra Exercise',",
  '    questions: AlgebraQuestions.all,',
  '    onRecordScore: (lesson, lang, idx, type, s, t, c, pct) =>',
  '        progressManager.recordExerciseScore(lesson, lang, subLessonIndex, type, s, t, c, pct),',
  '  );',
  '}',
  ''
)

# ─── Line ranges (1-based) ────────────────────────────────────────────────────
# After adding 11 import lines at top, original line N becomes N+11 in the file.
# But we read the file AFTER the import edit, so we work with the NEW line numbers.
#
# We need to re-find the class start lines by searching for their unique signatures.

function Find-LineNum([string[]]$fileLines, [string]$pattern) {
    for ($i = 0; $i -lt $fileLines.Count; $i++) {
        if ($fileLines[$i] -match [regex]::Escape($pattern)) { return $i + 1 }
    }
    return -1
}

$oldExStart  = Find-LineNum $lines 'class ExerciseScreen extends StatefulWidget {'
$oldExEnd    = (Find-LineNum $lines 'class SignDictionaryScreen extends StatelessWidget {') - 2
$wnStart     = Find-LineNum $lines 'class WholeNumbersExerciseScreen extends StatefulWidget {'
$cmpStart    = Find-LineNum $lines 'class ComparisonComprehensiveExerciseScreen extends StatefulWidget {'
$vlsLine     = Find-LineNum $lines 'class VideoLessonScreen extends StatefulWidget {'
$foStart     = Find-LineNum $lines 'class FundamentalOperationsExerciseScreen extends StatefulWidget {'
$flsLine     = Find-LineNum $lines 'class FractionLessonsScreen extends StatefulWidget {'
$frStart     = Find-LineNum $lines 'class FractionExerciseScreen extends StatefulWidget {'
$dnlsLine    = Find-LineNum $lines 'class DecimalNumbersLessonsScreen extends StatefulWidget {'
$decStart    = Find-LineNum $lines 'class DecimalExerciseScreen extends StatefulWidget {'
$plsLine     = Find-LineNum $lines 'class PercentageLessonsScreen extends StatefulWidget {'
$pctStart    = Find-LineNum $lines 'class PercentageExerciseScreen extends StatefulWidget {'
$alsLine     = Find-LineNum $lines 'class AlgebraLessonsScreen extends StatefulWidget {'
$algStart    = Find-LineNum $lines 'class AlgebraExerciseScreen extends StatefulWidget {'
$spsLine     = Find-LineNum $lines 'class StudentProgressScreen extends StatefulWidget {'

$wnEnd       = $cmpStart  - 1
$cmpEnd      = $vlsLine   - 1
$foEnd       = $flsLine   - 1
$frEnd       = $dnlsLine  - 1
$decEnd      = $plsLine   - 1
$pctEnd      = $alsLine   - 1
$algEnd      = $spsLine   - 1

Write-Host "Old ExerciseScreen : $oldExStart - $oldExEnd"
Write-Host "WholeNumbers       : $wnStart - $wnEnd"
Write-Host "Comparison         : $cmpStart - $cmpEnd"
Write-Host "FundamentalsOps    : $foStart - $foEnd"
Write-Host "Fraction           : $frStart - $frEnd"
Write-Host "Decimal            : $decStart - $decEnd"
Write-Host "Percentage         : $pctStart - $pctEnd"
Write-Host "Algebra            : $algStart - $algEnd"

# ─── Build output ─────────────────────────────────────────────────────────────

$insertedWn  = $false
$insertedCmp = $false
$insertedFo  = $false
$insertedFr  = $false
$insertedDec = $false
$insertedPct = $false
$insertedAlg = $false

for ($i = 0; $i -lt $lines.Count; $i++) {
    $ln = $i + 1

    # Skip old dead ExerciseScreen class
    if ($ln -ge $oldExStart -and $ln -le $oldExEnd) { continue }

    # WholeNumbers: insert wrapper at first line, skip rest of block
    if ($ln -eq $wnStart) {
        if (-not $insertedWn) { foreach ($l in $wn) { $out.Add($l) }; $insertedWn = $true }
        continue
    }
    if ($ln -gt $wnStart -and $ln -le $wnEnd) { continue }

    # Comparison: insert wrapper at first line, skip rest of block
    if ($ln -eq $cmpStart) {
        if (-not $insertedCmp) { foreach ($l in $cmp) { $out.Add($l) }; $insertedCmp = $true }
        continue
    }
    if ($ln -gt $cmpStart -and $ln -le $cmpEnd) { continue }

    # FundamentalsOps: insert wrapper at first line, skip rest of block
    if ($ln -eq $foStart) {
        if (-not $insertedFo) { foreach ($l in $fo) { $out.Add($l) }; $insertedFo = $true }
        continue
    }
    if ($ln -gt $foStart -and $ln -le $foEnd) { continue }

    # Fraction: insert wrapper at first line, skip rest of block
    if ($ln -eq $frStart) {
        if (-not $insertedFr) { foreach ($l in $fr) { $out.Add($l) }; $insertedFr = $true }
        continue
    }
    if ($ln -gt $frStart -and $ln -le $frEnd) { continue }

    # Decimal: insert wrapper at first line, skip rest of block
    if ($ln -eq $decStart) {
        if (-not $insertedDec) { foreach ($l in $dec) { $out.Add($l) }; $insertedDec = $true }
        continue
    }
    if ($ln -gt $decStart -and $ln -le $decEnd) { continue }

    # Percentage: insert wrapper at first line, skip rest of block
    if ($ln -eq $pctStart) {
        if (-not $insertedPct) { foreach ($l in $pct) { $out.Add($l) }; $insertedPct = $true }
        continue
    }
    if ($ln -gt $pctStart -and $ln -le $pctEnd) { continue }

    # Algebra: insert wrapper at first line, skip rest of block
    if ($ln -eq $algStart) {
        if (-not $insertedAlg) { foreach ($l in $alg) { $out.Add($l) }; $insertedAlg = $true }
        continue
    }
    if ($ln -gt $algStart -and $ln -le $algEnd) { continue }

    # Default: keep the line
    $out.Add($lines[$i])
}

Write-Host "Original lines: $($lines.Count)  ->  Output lines: $($out.Count)"
[System.IO.File]::WriteAllLines($file, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host "Done. main.dart rewritten."
