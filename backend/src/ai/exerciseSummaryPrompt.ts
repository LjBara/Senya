import { lessonContextToPromptBlock } from '../services/lessonResolve.service.js';
import type { mergeLessonContext } from '../services/lessonResolve.service.js';

type MergedCtx = ReturnType<typeof mergeLessonContext>;

export function buildExerciseSummaryPrompt(
  merged: MergedCtx,
  params: {
    exerciseTitle: string;
    score: number;
    totalQuestions: number;
    wrongQuestions: { type: string; summary: string }[];
  }
): string {
  const { exerciseTitle, score, totalQuestions, wrongQuestions } = params;
  const pct =
    totalQuestions > 0 ? Math.round((score / totalQuestions) * 100) : 0;

  const wrongBlock =
    wrongQuestions.length === 0
      ? 'The student answered all questions correctly.'
      : `Items the student got wrong (${wrongQuestions.length}):\n${JSON.stringify(
          wrongQuestions.map((w, i) => ({
            index: i + 1,
            questionType: w.type,
            questionSummary: w.summary,
          })),
          null,
          0
        )}`;

  return `You are a supportive elementary math tutor writing a brief post-exercise recap.

All output must be in English.

${lessonContextToPromptBlock(merged)}

Exercise title: ${exerciseTitle}
Score: ${score} / ${totalQuestions} (${pct}%).

${wrongBlock}

Task:
1. Write a short "summary" (2-4 sentences): encouraging, specific to this lesson topic, and mention strengths or what to review based on wrong items (if any). For a perfect score, celebrate and suggest one light optional review idea from the curriculum subtopics below.
2. Pick "recommendedSubtopics": an array of 0-5 strings naming subtopics the student should revisit. Prefer names from "Subtopics (curriculum)" above when they fit; otherwise use clear, short math labels. Use an empty array if nothing specific is needed (e.g. perfect score with no gaps).

Return ONLY valid JSON with exactly these keys:
{ "summary": string, "recommendedSubtopics": string[] }

Rules:
- No markdown, no code fences, no text outside the JSON object.
- "recommendedSubtopics" length at most 5; each string at most 100 characters.
- "summary" at most 600 characters.`;
}
